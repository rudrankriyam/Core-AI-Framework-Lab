from pathlib import Path

import torch
from huggingface_hub import hf_hub_download
from safetensors.torch import load_file

from t3 import (
    T3_MAX_CONTEXT_LENGTH,
    T3_STOP_SPEECH_TOKEN,
    create_cache_tensors,
    load_t3_components,
    load_t3_embedding_modules,
    load_t3_transformer,
)

REPO_ID = "ResembleAI/chatterbox-turbo"


def _paths() -> tuple[Path, Path]:
    return (
        Path(hf_hub_download(REPO_ID, "t3_turbo_v1.safetensors")),
        Path(hf_hub_download(REPO_ID, "conds.pt")),
    )


def _source_model(checkpoint_path: Path):
    from chatterbox.models.t3.modules.t3_config import T3Config
    from chatterbox.models.t3.t3 import T3

    hp = T3Config(text_tokens_dict_size=50276)
    hp.llama_config_name = "GPT2_medium"
    hp.speech_tokens_dict_size = 6563
    hp.input_pos_emb = None
    hp.speech_cond_prompt_len = 375
    hp.use_perceiver_resampler = False
    hp.emotion_adv = False

    model = T3(hp)
    model.load_state_dict(load_file(checkpoint_path))
    del model.tfmr.wte
    return model.eval()


def test_t3_prefill_and_decode_match_hugging_face() -> None:
    from chatterbox.tts_turbo import Conditionals

    checkpoint_path, conditionals_path = _paths()
    source = _source_model(checkpoint_path)
    components = load_t3_components(
        checkpoint_path,
        conditionals_path,
        dtype=torch.float32,
    )
    conditionals = Conditionals.load(conditionals_path)

    text_tokens = torch.tensor(
        [[1212, 318, 257, 1332, 13]],
        dtype=torch.int64,
    )
    start_token = torch.full_like(text_tokens[:, :1], 6561)
    source_embeddings, _ = source.prepare_input_embeds(
        t3_cond=conditionals.t3,
        text_tokens=text_tokens,
        speech_tokens=start_token,
        cfg_weight=0.0,
    )
    actual_embeddings = components.prefill(text_tokens)
    torch.testing.assert_close(
        actual_embeddings,
        source_embeddings,
        atol=0,
        rtol=0,
    )

    k_cache, v_cache = create_cache_tensors(dtype=torch.float32)
    prefill_positions = torch.arange(
        actual_embeddings.shape[1],
        dtype=torch.int32,
    ).unsqueeze(0)

    with torch.inference_mode():
        source_prefill = source.tfmr(
            inputs_embeds=source_embeddings,
            use_cache=True,
        )
        expected_prefill_logits = source.speech_head(
            source_prefill.last_hidden_state[:, -1:]
        )
        actual_prefill_logits = components.transformer(
            actual_embeddings,
            prefill_positions,
            k_cache,
            v_cache,
        )[:, -1:]

    torch.testing.assert_close(
        actual_prefill_logits,
        expected_prefill_logits,
        atol=2e-4,
        rtol=2e-4,
    )

    next_token = expected_prefill_logits.argmax(dim=-1)
    assert int(next_token.item()) != T3_STOP_SPEECH_TOKEN
    source_decode_embedding = source.speech_emb(next_token)
    actual_decode_embedding = components.decode(next_token)
    torch.testing.assert_close(
        actual_decode_embedding,
        source_decode_embedding,
        atol=0,
        rtol=0,
    )

    decode_positions = torch.arange(
        actual_embeddings.shape[1] + 1,
        dtype=torch.int32,
    ).unsqueeze(0)
    with torch.inference_mode():
        source_decode = source.tfmr(
            inputs_embeds=source_decode_embedding,
            past_key_values=source_prefill.past_key_values,
            use_cache=True,
        )
        expected_decode_logits = source.speech_head(
            source_decode.last_hidden_state
        )
        actual_decode_logits = components.transformer(
            actual_decode_embedding,
            decode_positions,
            k_cache,
            v_cache,
        )

    torch.testing.assert_close(
        actual_decode_logits,
        expected_decode_logits,
        atol=3e-4,
        rtol=3e-4,
    )


def test_cache_shape_matches_context_limit() -> None:
    k_cache, v_cache = create_cache_tensors(dtype=torch.float16)
    assert k_cache.shape == v_cache.shape
    assert k_cache.shape[-2] == T3_MAX_CONTEXT_LENGTH


def test_delta_cache_returns_only_new_key_value_slices() -> None:
    checkpoint_path, conditionals_path = _paths()
    prefill, decode = load_t3_embedding_modules(
        checkpoint_path,
        conditionals_path,
        dtype=torch.float32,
    )
    full_cache_transformer = load_t3_transformer(
        checkpoint_path,
        dtype=torch.float32,
        explicit_cache=True,
    )
    delta_cache_transformer = load_t3_transformer(
        checkpoint_path,
        dtype=torch.float32,
        delta_cache=True,
    )

    text_tokens = torch.tensor(
        [[1212, 318, 257, 1332, 13]],
        dtype=torch.int64,
    )
    embeddings = prefill(text_tokens)
    positions = torch.arange(
        embeddings.shape[1],
        dtype=torch.int32,
    ).unsqueeze(0)
    full_key_cache, full_value_cache = create_cache_tensors(
        dtype=torch.float32
    )
    delta_key_cache, delta_value_cache = create_cache_tensors(
        dtype=torch.float32
    )

    with torch.inference_mode():
        full_logits, full_key_cache, full_value_cache = (
            full_cache_transformer(
                embeddings,
                positions,
                full_key_cache,
                full_value_cache,
            )
        )
        delta_logits, key_updates, value_updates = (
            delta_cache_transformer(
                embeddings,
                positions,
                delta_key_cache,
                delta_value_cache,
            )
        )

    query_length = embeddings.shape[1]
    assert key_updates.shape[-2] == query_length
    assert value_updates.shape == key_updates.shape
    torch.testing.assert_close(delta_logits, full_logits)
    torch.testing.assert_close(
        key_updates,
        full_key_cache[..., :query_length, :],
    )
    torch.testing.assert_close(
        value_updates,
        full_value_cache[..., :query_length, :],
    )

    delta_key_cache[..., :query_length, :] = key_updates
    delta_value_cache[..., :query_length, :] = value_updates
    next_token = full_logits[:, -1:].argmax(dim=-1)
    decode_embeddings = decode(next_token)
    decode_positions = torch.arange(
        query_length + 1,
        dtype=torch.int32,
    ).unsqueeze(0)

    with torch.inference_mode():
        full_decode_logits, full_key_cache, full_value_cache = (
            full_cache_transformer(
                decode_embeddings,
                decode_positions,
                full_key_cache,
                full_value_cache,
            )
        )
        delta_decode_logits, key_updates, value_updates = (
            delta_cache_transformer(
                decode_embeddings,
                decode_positions,
                delta_key_cache,
                delta_value_cache,
            )
        )

    assert key_updates.shape[-2] == 1
    assert value_updates.shape[-2] == 1
    torch.testing.assert_close(delta_decode_logits, full_decode_logits)
    torch.testing.assert_close(
        key_updates,
        full_key_cache[..., query_length : query_length + 1, :],
    )
    torch.testing.assert_close(
        value_updates,
        full_value_cache[..., query_length : query_length + 1, :],
    )


def test_static_decode_matches_variable_length_decode() -> None:
    checkpoint_path, conditionals_path = _paths()
    prefill, decode = load_t3_embedding_modules(
        checkpoint_path,
        conditionals_path,
        dtype=torch.float32,
    )
    full_cache_transformer = load_t3_transformer(
        checkpoint_path,
        dtype=torch.float32,
        explicit_cache=True,
    )
    static_decode_transformer = load_t3_transformer(
        checkpoint_path,
        dtype=torch.float32,
        static_decode_cache=True,
    )

    text_tokens = torch.tensor(
        [[1212, 318, 257, 1332, 13]],
        dtype=torch.int64,
    )
    embeddings = prefill(text_tokens)
    query_length = embeddings.shape[1]
    positions = torch.arange(
        query_length,
        dtype=torch.int32,
    ).unsqueeze(0)
    key_cache, value_cache = create_cache_tensors(dtype=torch.float32)

    with torch.inference_mode():
        prefill_logits, key_cache, value_cache = full_cache_transformer(
            embeddings,
            positions,
            key_cache,
            value_cache,
        )

    next_token = prefill_logits[:, -1:].argmax(dim=-1)
    decode_embeddings = decode(next_token)
    variable_positions = torch.arange(
        query_length + 1,
        dtype=torch.int32,
    ).unsqueeze(0)
    static_position = torch.tensor(
        [[query_length]],
        dtype=torch.int32,
    )

    with torch.inference_mode():
        expected_logits, expected_key_cache, expected_value_cache = (
            full_cache_transformer(
                decode_embeddings,
                variable_positions,
                key_cache,
                value_cache,
            )
        )
        actual_logits, key_updates, value_updates = (
            static_decode_transformer(
                decode_embeddings,
                static_position,
                key_cache,
                value_cache,
            )
        )

    torch.testing.assert_close(
        actual_logits,
        expected_logits,
        atol=3e-4,
        rtol=3e-4,
    )
    torch.testing.assert_close(
        key_updates,
        expected_key_cache[..., query_length : query_length + 1, :],
    )
    torch.testing.assert_close(
        value_updates,
        expected_value_cache[..., query_length : query_length + 1, :],
    )
