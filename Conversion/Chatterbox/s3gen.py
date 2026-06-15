from pathlib import Path

import torch
import torch.nn.functional as F
from safetensors import safe_open
from torch import nn

from vocoder import replace_conv1d_modules

S3GEN_GENERATED_TOKENS = 256
S3GEN_MEL_FRAMES_PER_TOKEN = 2
S3GEN_PROMPT_TOKENS = 250
S3GEN_PROMPT_MEL_FRAMES = 500
S3GEN_TOTAL_TOKENS = S3GEN_PROMPT_TOKENS + S3GEN_GENERATED_TOKENS
S3GEN_TOTAL_MEL_FRAMES = (
    S3GEN_TOTAL_TOKENS * S3GEN_MEL_FRAMES_PER_TOKEN
)
S3GEN_GENERATED_MEL_FRAMES = (
    S3GEN_GENERATED_TOKENS * S3GEN_MEL_FRAMES_PER_TOKEN
)


class CoreAIConditionalDecoder(nn.Module):
    def __init__(self, decoder: nn.Module) -> None:
        super().__init__()
        self.decoder = decoder

    def forward(
        self,
        x: torch.Tensor,
        mask: torch.Tensor,
        mu: torch.Tensor,
        t: torch.Tensor,
        spks: torch.Tensor,
        cond: torch.Tensor,
        r: torch.Tensor,
    ) -> torch.Tensor:
        decoder = self.decoder
        time_embedding = decoder.time_embeddings(t).to(t.dtype)
        time_embedding = decoder.time_mlp(time_embedding)

        end_embedding = decoder.time_embeddings(r).to(time_embedding.dtype)
        end_embedding = decoder.time_mlp(end_embedding)
        time_embedding = decoder.time_embed_mixer(
            torch.cat((time_embedding, end_embedding), dim=1)
        )

        x = torch.cat((x, mu), dim=1)
        speaker = spks.unsqueeze(2).expand(-1, -1, x.shape[-1])
        x = torch.cat((x, speaker, cond), dim=1)

        hiddens: list[torch.Tensor] = []
        masks = [mask]
        for resnet, transformer_blocks, downsample in decoder.down_blocks:
            block_mask = masks[-1]
            x = resnet(x, block_mask, time_embedding)
            x = x.transpose(1, 2).contiguous()
            attention_bias = torch.zeros_like(
                block_mask,
                dtype=x.dtype,
            )
            for transformer_block in transformer_blocks:
                x = transformer_block(
                    hidden_states=x,
                    attention_mask=attention_bias,
                    timestep=time_embedding,
                )
            x = x.transpose(1, 2).contiguous()
            hiddens.append(x)
            x = downsample(x * block_mask)
            masks.append(block_mask[:, :, ::2])

        masks = masks[:-1]
        middle_mask = masks[-1]
        for resnet, transformer_blocks in decoder.mid_blocks:
            x = resnet(x, middle_mask, time_embedding)
            x = x.transpose(1, 2).contiguous()
            attention_bias = torch.zeros_like(
                middle_mask,
                dtype=x.dtype,
            )
            for transformer_block in transformer_blocks:
                x = transformer_block(
                    hidden_states=x,
                    attention_mask=attention_bias,
                    timestep=time_embedding,
                )
            x = x.transpose(1, 2).contiguous()

        for resnet, transformer_blocks, upsample in decoder.up_blocks:
            block_mask = masks.pop()
            skip = hiddens.pop()
            x = torch.cat((x[:, :, :skip.shape[-1]], skip), dim=1)
            x = resnet(x, block_mask, time_embedding)
            x = x.transpose(1, 2).contiguous()
            attention_bias = torch.zeros_like(
                block_mask,
                dtype=x.dtype,
            )
            for transformer_block in transformer_blocks:
                x = transformer_block(
                    hidden_states=x,
                    attention_mask=attention_bias,
                    timestep=time_embedding,
                )
            x = x.transpose(1, 2).contiguous()
            x = upsample(x * block_mask)

        x = decoder.final_block(x, block_mask)
        output = decoder.final_proj(x * block_mask)
        return output * mask


def create_s3gen_flow() -> nn.Module:
    from chatterbox.models.s3gen.configs import CFM_PARAMS
    from chatterbox.models.s3gen.decoder import ConditionalDecoder
    from chatterbox.models.s3gen.flow import CausalMaskedDiffWithXvec
    from chatterbox.models.s3gen.flow_matching import (
        CausalConditionalCFM,
    )
    from chatterbox.models.s3gen.transformer.upsample_encoder import (
        UpsampleConformerEncoder,
    )

    encoder = UpsampleConformerEncoder(
        output_size=512,
        attention_heads=8,
        linear_units=2048,
        num_blocks=6,
        dropout_rate=0.1,
        positional_dropout_rate=0.1,
        attention_dropout_rate=0.1,
        normalize_before=True,
        input_layer="linear",
        pos_enc_layer_type="rel_pos_espnet",
        selfattention_layer_type="rel_selfattn",
        input_size=512,
        use_cnn_module=False,
        macaron_style=False,
    )
    estimator = ConditionalDecoder(
        in_channels=320,
        out_channels=80,
        causal=True,
        channels=[256],
        dropout=0.0,
        attention_head_dim=64,
        n_blocks=4,
        num_mid_blocks=12,
        num_heads=8,
        act_fn="gelu",
        meanflow=True,
    )
    decoder = CausalConditionalCFM(
        spk_emb_dim=80,
        cfm_params=CFM_PARAMS,
        estimator=estimator,
    )
    return CausalMaskedDiffWithXvec(
        encoder=encoder,
        decoder=decoder,
    )


def load_s3gen_flow(
    checkpoint_path: Path,
    *,
    dtype: torch.dtype = torch.float32,
    coreai_compatible: bool = False,
) -> nn.Module:
    flow = create_s3gen_flow()
    with safe_open(checkpoint_path, framework="pt", device="cpu") as checkpoint:
        state_dict = {
            key.removeprefix("flow."): checkpoint.get_tensor(key)
            for key in checkpoint.keys()
            if key.startswith("flow.")
        }
    flow.load_state_dict(state_dict, strict=True)
    flow = flow.eval().to(dtype=dtype)
    if coreai_compatible:
        replace_conv1d_modules(flow)
        flow.decoder.estimator = CoreAIConditionalDecoder(
            flow.decoder.estimator
        )
    return flow


class CoreAIS3Gen(nn.Module):
    def __init__(
        self,
        flow: nn.Module,
        prompt_token: torch.Tensor,
        prompt_feat: torch.Tensor,
        embedding: torch.Tensor,
    ) -> None:
        super().__init__()
        self.flow = flow
        self.register_buffer(
            "prompt_token",
            prompt_token.to(dtype=torch.int32),
        )
        self.register_buffer(
            "prompt_feat",
            prompt_feat,
        )
        self.register_buffer(
            "embedding",
            embedding,
        )
        self.register_buffer(
            "token_lengths",
            torch.tensor([S3GEN_TOTAL_TOKENS], dtype=torch.int32),
        )
        self.register_buffer(
            "token_mask",
            torch.ones(
                (1, 1, S3GEN_TOTAL_TOKENS),
                dtype=torch.bool,
            ),
        )
        self.register_buffer(
            "mel_mask",
            torch.ones(
                (1, 1, S3GEN_TOTAL_MEL_FRAMES),
                dtype=torch.bool,
            ),
        )
        self.register_buffer(
            "mask",
            torch.ones(
                (1, 1, S3GEN_TOTAL_MEL_FRAMES),
                dtype=prompt_feat.dtype,
            ),
        )
        self.register_buffer(
            "zero_generated_condition",
            torch.zeros(
                (1, 80, S3GEN_GENERATED_MEL_FRAMES),
                dtype=prompt_feat.dtype,
            ),
        )

    def encode_tokens(self, token_embeddings: torch.Tensor) -> torch.Tensor:
        encoder = self.flow.encoder
        encoded = token_embeddings
        if encoder.global_cmvn is not None:
            encoded = encoder.global_cmvn(encoded)

        encoded, position, _ = encoder.embed(encoded, self.token_mask)
        encoded = encoder.pre_lookahead_layer(encoded)
        encoded = encoder.forward_layers(
            encoded,
            self.token_mask,
            position,
            self.token_mask,
        )

        encoded = encoded.transpose(1, 2).contiguous()
        encoded, _ = encoder.up_layer(encoded, self.token_lengths)
        encoded = encoded.transpose(1, 2).contiguous()
        encoded, position, _ = encoder.up_embed(encoded, self.mel_mask)
        encoded = encoder.forward_up_layers(
            encoded,
            self.mel_mask,
            position,
            self.mel_mask,
        )

        if encoder.normalize_before:
            encoded = encoder.after_norm(encoded)
        return encoded

    def forward(
        self,
        speech_tokens: torch.Tensor,
        noise: torch.Tensor,
    ) -> torch.Tensor:
        speaker = F.normalize(self.embedding, dim=1)
        speaker = self.flow.spk_embed_affine_layer(speaker)

        tokens = torch.cat(
            (self.prompt_token, speech_tokens),
            dim=1,
        )
        token_embeddings = self.flow.input_embedding(tokens)
        encoded = self.encode_tokens(token_embeddings)
        mu = self.flow.encoder_proj(encoded).transpose(1, 2)
        condition = torch.cat(
            (
                self.prompt_feat.transpose(1, 2),
                self.zero_generated_condition,
            ),
            dim=2,
        )

        time_zero = torch.zeros(
            (1,),
            dtype=noise.dtype,
            device=noise.device,
        )
        time_half = torch.full(
            (1,),
            0.5,
            dtype=noise.dtype,
            device=noise.device,
        )
        time_one = torch.ones(
            (1,),
            dtype=noise.dtype,
            device=noise.device,
        )

        derivative = self.flow.decoder.estimator(
            noise,
            mask=self.mask,
            mu=mu,
            t=time_zero,
            spks=speaker,
            cond=condition,
            r=time_half,
        )
        sample = noise + 0.5 * derivative
        derivative = self.flow.decoder.estimator(
            sample,
            mask=self.mask,
            mu=mu,
            t=time_half,
            spks=speaker,
            cond=condition,
            r=time_one,
        )
        sample = sample + 0.5 * derivative
        return sample[:, :, S3GEN_PROMPT_MEL_FRAMES:]


def load_s3gen_model(
    checkpoint_path: Path,
    conditionals_path: Path,
    *,
    dtype: torch.dtype = torch.float32,
    coreai_compatible: bool = False,
) -> CoreAIS3Gen:
    from chatterbox.tts_turbo import Conditionals

    conditionals = Conditionals.load(conditionals_path)
    flow = load_s3gen_flow(
        checkpoint_path,
        dtype=dtype,
        coreai_compatible=coreai_compatible,
    )
    return CoreAIS3Gen(
        flow,
        conditionals.gen["prompt_token"],
        conditionals.gen["prompt_feat"].to(dtype=dtype),
        conditionals.gen["embedding"].to(dtype=dtype),
    ).eval()


def reference_inputs(
    *,
    dtype: torch.dtype = torch.float32,
) -> tuple[torch.Tensor, torch.Tensor]:
    return (
        torch.full(
            (1, S3GEN_GENERATED_TOKENS),
            4299,
            dtype=torch.int32,
        ),
        torch.zeros(
            (1, 80, S3GEN_TOTAL_MEL_FRAMES),
            dtype=dtype,
        ),
    )
