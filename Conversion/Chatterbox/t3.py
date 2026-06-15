import math
from dataclasses import dataclass
from pathlib import Path

import torch
import torch.nn.functional as F
from coreai_torch.composite_ops import SDPA
from safetensors import safe_open
from torch import nn

from coreai_state import (
    DeltaKVCache,
    ExplicitKVCache,
    KVCache,
    StaticDecodeKVCache,
)

T3_HIDDEN_SIZE = 1024
T3_INTERMEDIATE_SIZE = 4096
T3_NUM_HEADS = 16
T3_HEAD_DIM = 64
T3_NUM_LAYERS = 24
T3_TEXT_VOCAB_SIZE = 50276
T3_SPEECH_VOCAB_SIZE = 6563
T3_START_SPEECH_TOKEN = 6561
T3_STOP_SPEECH_TOKEN = 6562
T3_CONDITION_TOKEN_COUNT = 376
T3_MAX_TEXT_TOKENS = 256
T3_MAX_CONTEXT_LENGTH = 768


@dataclass(frozen=True)
class T3Components:
    prefill: nn.Module
    decode: nn.Module
    transformer: nn.Module


class GPT2NewGELU(nn.Module):
    def forward(self, value: torch.Tensor) -> torch.Tensor:
        coefficient = math.sqrt(2 / math.pi)
        return 0.5 * value * (
            1 + torch.tanh(coefficient * (value + 0.044715 * value.pow(3)))
        )


class CoreAIGPT2Attention(nn.Module):
    def __init__(
        self,
        layer_index: int,
        *,
        use_hf_attention: bool,
    ) -> None:
        super().__init__()
        self.layer_index = layer_index
        self.qkv_projection = nn.Linear(
            T3_HIDDEN_SIZE,
            3 * T3_HIDDEN_SIZE,
            bias=True,
        )
        self.output_projection = nn.Linear(
            T3_HIDDEN_SIZE,
            T3_HIDDEN_SIZE,
            bias=True,
        )
        self.attention = SDPA(
            is_causal=True,
            _use_hf_impl=use_hf_attention,
        )

    def forward(
        self,
        value: torch.Tensor,
        position_ids: torch.Tensor,
        cache,
    ) -> torch.Tensor:
        batch_size, query_length, _ = value.shape
        qkv = self.qkv_projection(value)
        qkv = qkv.reshape(
            batch_size,
            query_length,
            3,
            T3_NUM_HEADS,
            T3_HEAD_DIM,
        ).permute(0, 2, 3, 1, 4)

        query = qkv.narrow(1, 0, 1).squeeze(1)
        key = qkv.narrow(1, 1, 1).squeeze(1)
        result_value = qkv.narrow(1, 2, 1).squeeze(1)

        sequence_length = position_ids.shape[-1]
        offset = sequence_length - query_length
        key, result_value = cache.update_and_fetch(
            self.layer_index,
            offset,
            key,
            result_value,
            seq_len=sequence_length,
            query_len=query_length,
        )

        result = self.attention(
            query,
            key,
            result_value,
            attn_mask=getattr(cache, "attention_mask", None),
        )
        result = result.permute(0, 2, 1, 3).reshape(
            batch_size,
            query_length,
            T3_HIDDEN_SIZE,
        )
        return self.output_projection(result)


class CoreAIGPT2MLP(nn.Module):
    def __init__(self) -> None:
        super().__init__()
        self.input_projection = nn.Linear(
            T3_HIDDEN_SIZE,
            T3_INTERMEDIATE_SIZE,
            bias=True,
        )
        self.activation = GPT2NewGELU()
        self.output_projection = nn.Linear(
            T3_INTERMEDIATE_SIZE,
            T3_HIDDEN_SIZE,
            bias=True,
        )

    def forward(self, value: torch.Tensor) -> torch.Tensor:
        return self.output_projection(
            self.activation(self.input_projection(value))
        )


class CoreAIGPT2Block(nn.Module):
    def __init__(
        self,
        layer_index: int,
        *,
        use_hf_attention: bool,
    ) -> None:
        super().__init__()
        self.input_norm = nn.LayerNorm(T3_HIDDEN_SIZE, eps=1e-5)
        self.attention = CoreAIGPT2Attention(
            layer_index,
            use_hf_attention=use_hf_attention,
        )
        self.post_attention_norm = nn.LayerNorm(T3_HIDDEN_SIZE, eps=1e-5)
        self.mlp = CoreAIGPT2MLP()

    def forward(
        self,
        value: torch.Tensor,
        position_ids: torch.Tensor,
        cache,
    ) -> torch.Tensor:
        value = value + self.attention(
            self.input_norm(value),
            position_ids,
            cache,
        )
        return value + self.mlp(self.post_attention_norm(value))


class CoreAIT3Transformer(nn.Module):
    def __init__(
        self,
        max_context_length: int = T3_MAX_CONTEXT_LENGTH,
        *,
        use_hf_attention: bool = False,
    ) -> None:
        super().__init__()
        self.max_context_length = max_context_length
        self.position_embedding = nn.Embedding(
            max_context_length,
            T3_HIDDEN_SIZE,
        )
        self.blocks = nn.ModuleList(
            CoreAIGPT2Block(
                index,
                use_hf_attention=use_hf_attention,
            )
            for index in range(T3_NUM_LAYERS)
        )
        self.final_norm = nn.LayerNorm(T3_HIDDEN_SIZE, eps=1e-5)
        self.speech_head = nn.Linear(
            T3_HIDDEN_SIZE,
            T3_SPEECH_VOCAB_SIZE,
            bias=True,
        )

    def forward(
        self,
        input_embeddings: torch.Tensor,
        position_ids: torch.Tensor,
        k_cache: torch.Tensor,
        v_cache: torch.Tensor,
    ) -> torch.Tensor:
        query_length = input_embeddings.shape[1]
        sequence_length = position_ids.shape[-1]
        offset = sequence_length - query_length
        query_positions = position_ids.narrow(-1, offset, query_length)

        cache = KVCache(k_cache, v_cache)
        return self._forward_with_cache(
            input_embeddings,
            query_positions,
            position_ids,
            cache,
        )

    def _forward_with_cache(
        self,
        input_embeddings: torch.Tensor,
        query_positions: torch.Tensor,
        position_ids: torch.Tensor,
        cache,
    ) -> torch.Tensor:
        value = input_embeddings + self.position_embedding(query_positions)
        for block in self.blocks:
            value = block(value, position_ids, cache)

        return self.speech_head(self.final_norm(value))


class CoreAIT3ExplicitTransformer(CoreAIT3Transformer):
    def forward(
        self,
        input_embeddings: torch.Tensor,
        position_ids: torch.Tensor,
        k_cache: torch.Tensor,
        v_cache: torch.Tensor,
    ) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
        query_length = input_embeddings.shape[1]
        sequence_length = position_ids.shape[-1]
        offset = sequence_length - query_length
        query_positions = position_ids.narrow(-1, offset, query_length)
        cache = ExplicitKVCache(k_cache, v_cache)
        logits = self._forward_with_cache(
            input_embeddings,
            query_positions,
            position_ids,
            cache,
        )
        return logits, cache.key_cache, cache.value_cache


class CoreAIT3DeltaTransformer(CoreAIT3Transformer):
    def forward(
        self,
        input_embeddings: torch.Tensor,
        position_ids: torch.Tensor,
        k_cache: torch.Tensor,
        v_cache: torch.Tensor,
    ) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
        query_length = input_embeddings.shape[1]
        sequence_length = position_ids.shape[-1]
        offset = sequence_length - query_length
        query_positions = position_ids.narrow(-1, offset, query_length)
        cache = DeltaKVCache(k_cache, v_cache)
        logits = self._forward_with_cache(
            input_embeddings,
            query_positions,
            position_ids,
            cache,
        )
        key_updates, value_updates = cache.stacked_updates()
        return logits, key_updates, value_updates


class CoreAIT3StaticDecodeTransformer(CoreAIT3Transformer):
    def forward(
        self,
        input_embeddings: torch.Tensor,
        position_ids: torch.Tensor,
        k_cache: torch.Tensor,
        v_cache: torch.Tensor,
    ) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
        position = position_ids.reshape(-1)[0]
        cache = StaticDecodeKVCache(
            k_cache,
            v_cache,
            position,
        )
        logits = self._forward_with_cache(
            input_embeddings,
            position_ids,
            position_ids,
            cache,
        )
        key_updates, value_updates = cache.stacked_updates()
        return logits, key_updates, value_updates


class CoreAIT3PrefillEmbeddings(nn.Module):
    def __init__(
        self,
        condition_embeddings: torch.Tensor,
        start_speech_embedding: torch.Tensor,
    ) -> None:
        super().__init__()
        self.text_embedding = nn.Embedding(
            T3_TEXT_VOCAB_SIZE,
            T3_HIDDEN_SIZE,
        )
        self.register_buffer(
            "condition_embeddings",
            condition_embeddings,
        )
        self.register_buffer(
            "start_speech_embedding",
            start_speech_embedding,
        )

    def forward(self, text_tokens: torch.Tensor) -> torch.Tensor:
        text_embeddings = self.text_embedding(text_tokens)
        return torch.cat(
            (
                self.condition_embeddings,
                text_embeddings,
                self.start_speech_embedding,
            ),
            dim=1,
        )


class CoreAIT3DecodeEmbedding(nn.Module):
    def __init__(self) -> None:
        super().__init__()
        self.speech_embedding = nn.Embedding(
            T3_SPEECH_VOCAB_SIZE,
            T3_HIDDEN_SIZE,
        )

    def forward(self, speech_token: torch.Tensor) -> torch.Tensor:
        return self.speech_embedding(speech_token)


def create_cache_tensors(
    *,
    max_context_length: int = T3_MAX_CONTEXT_LENGTH,
    dtype: torch.dtype = torch.float16,
) -> tuple[torch.Tensor, torch.Tensor]:
    shape = (
        T3_NUM_LAYERS,
        1,
        T3_NUM_HEADS,
        max_context_length,
        T3_HEAD_DIM,
    )
    return (
        torch.zeros(shape, dtype=dtype),
        torch.zeros(shape, dtype=dtype),
    )


def load_t3_components(
    checkpoint_path: Path,
    conditionals_path: Path,
    *,
    max_context_length: int = T3_MAX_CONTEXT_LENGTH,
    dtype: torch.dtype = torch.float32,
) -> T3Components:
    prefill, decode = load_t3_embedding_modules(
        checkpoint_path,
        conditionals_path,
        dtype=dtype,
    )
    transformer = load_t3_transformer(
        checkpoint_path,
        max_context_length=max_context_length,
        dtype=dtype,
    )
    return T3Components(
        prefill=prefill,
        decode=decode,
        transformer=transformer,
    )


def load_t3_embedding_modules(
    checkpoint_path: Path,
    conditionals_path: Path,
    *,
    dtype: torch.dtype = torch.float32,
) -> tuple[nn.Module, nn.Module]:
    from chatterbox.tts_turbo import Conditionals

    conditionals = Conditionals.load(conditionals_path)
    prompt_tokens = conditionals.t3.cond_prompt_speech_tokens
    if prompt_tokens is None:
        raise ValueError("The built-in T3 prompt tokens are missing.")

    with safe_open(checkpoint_path, framework="pt", device="cpu") as checkpoint:
        speech_embedding = checkpoint.get_tensor("speech_emb.weight")
        speaker_embedding = conditionals.t3.speaker_emb
        speaker_condition = F.linear(
            speaker_embedding,
            checkpoint.get_tensor("cond_enc.spkr_enc.weight"),
            checkpoint.get_tensor("cond_enc.spkr_enc.bias"),
        ).unsqueeze(1)
        prompt_condition = F.embedding(prompt_tokens, speech_embedding)
        condition_embeddings = torch.cat(
            (speaker_condition, prompt_condition),
            dim=1,
        )
        start_speech_embedding = speech_embedding[
            T3_START_SPEECH_TOKEN
        ].reshape(1, 1, T3_HIDDEN_SIZE)

        prefill = CoreAIT3PrefillEmbeddings(
            condition_embeddings.to(dtype=dtype),
            start_speech_embedding.to(dtype=dtype),
        ).to(dtype=dtype)
        decode = CoreAIT3DecodeEmbedding().to(dtype=dtype)

        _copy_parameter(
            prefill.text_embedding.weight,
            checkpoint.get_tensor("text_emb.weight"),
        )
        _copy_parameter(decode.speech_embedding.weight, speech_embedding)

    return prefill.eval(), decode.eval()


def load_t3_transformer(
    checkpoint_path: Path,
    *,
    max_context_length: int = T3_MAX_CONTEXT_LENGTH,
    dtype: torch.dtype = torch.float32,
    explicit_cache: bool = False,
    delta_cache: bool = False,
    static_decode_cache: bool = False,
) -> nn.Module:
    cache_modes = sum(
        (explicit_cache, delta_cache, static_decode_cache)
    )
    if cache_modes > 1:
        raise ValueError("Choose one cache mode.")
    if static_decode_cache:
        transformer_type = CoreAIT3StaticDecodeTransformer
    elif delta_cache:
        transformer_type = CoreAIT3DeltaTransformer
    elif explicit_cache:
        transformer_type = CoreAIT3ExplicitTransformer
    else:
        transformer_type = CoreAIT3Transformer
    transformer = transformer_type(
        max_context_length=max_context_length,
        use_hf_attention=(
            explicit_cache or delta_cache or static_decode_cache
        ),
    ).to(dtype=dtype)

    with safe_open(checkpoint_path, framework="pt", device="cpu") as checkpoint:
        _copy_parameter(
            transformer.position_embedding.weight,
            checkpoint.get_tensor("tfmr.wpe.weight")[
                :max_context_length
            ],
        )
        _copy_parameter(
            transformer.final_norm.weight,
            checkpoint.get_tensor("tfmr.ln_f.weight"),
        )
        _copy_parameter(
            transformer.final_norm.bias,
            checkpoint.get_tensor("tfmr.ln_f.bias"),
        )
        _copy_parameter(
            transformer.speech_head.weight,
            checkpoint.get_tensor("speech_head.weight"),
        )
        _copy_parameter(
            transformer.speech_head.bias,
            checkpoint.get_tensor("speech_head.bias"),
        )

        for index, block in enumerate(transformer.blocks):
            prefix = f"tfmr.h.{index}"
            _copy_parameter(
                block.input_norm.weight,
                checkpoint.get_tensor(f"{prefix}.ln_1.weight"),
            )
            _copy_parameter(
                block.input_norm.bias,
                checkpoint.get_tensor(f"{prefix}.ln_1.bias"),
            )
            _copy_parameter(
                block.attention.qkv_projection.weight,
                checkpoint.get_tensor(
                    f"{prefix}.attn.c_attn.weight"
                ).transpose(0, 1),
            )
            _copy_parameter(
                block.attention.qkv_projection.bias,
                checkpoint.get_tensor(
                    f"{prefix}.attn.c_attn.bias"
                ),
            )
            _copy_parameter(
                block.attention.output_projection.weight,
                checkpoint.get_tensor(
                    f"{prefix}.attn.c_proj.weight"
                ).transpose(0, 1),
            )
            _copy_parameter(
                block.attention.output_projection.bias,
                checkpoint.get_tensor(
                    f"{prefix}.attn.c_proj.bias"
                ),
            )
            _copy_parameter(
                block.post_attention_norm.weight,
                checkpoint.get_tensor(f"{prefix}.ln_2.weight"),
            )
            _copy_parameter(
                block.post_attention_norm.bias,
                checkpoint.get_tensor(f"{prefix}.ln_2.bias"),
            )
            _copy_parameter(
                block.mlp.input_projection.weight,
                checkpoint.get_tensor(
                    f"{prefix}.mlp.c_fc.weight"
                ).transpose(0, 1),
            )
            _copy_parameter(
                block.mlp.input_projection.bias,
                checkpoint.get_tensor(f"{prefix}.mlp.c_fc.bias"),
            )
            _copy_parameter(
                block.mlp.output_projection.weight,
                checkpoint.get_tensor(
                    f"{prefix}.mlp.c_proj.weight"
                ).transpose(0, 1),
            )
            _copy_parameter(
                block.mlp.output_projection.bias,
                checkpoint.get_tensor(f"{prefix}.mlp.c_proj.bias"),
            )

    return transformer.eval()


def _copy_parameter(
    destination: torch.Tensor,
    source: torch.Tensor,
) -> None:
    if destination.shape != source.shape:
        raise ValueError(
            f"Shape mismatch: {tuple(destination.shape)} != "
            f"{tuple(source.shape)}"
        )
    with torch.no_grad():
        destination.copy_(
            source.to(device=destination.device, dtype=destination.dtype)
        )
