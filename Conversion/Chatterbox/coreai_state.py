# Copyright 2026 Apple Inc.
#
# Use of this source code is governed by a BSD-3-clause license that can
# be found at https://opensource.org/licenses/BSD-3-Clause
#
# Adapted from apple/coreai-models at commit
# 02a8eddefbbb0754d6752f6f3a8bdf2fae2e85b3.

from collections.abc import Callable

import torch
from coreai._compiler.dialects import coreai
from coreai._compiler.ir import Location, Value
from torch import Tensor, fx
from torch._higher_order_ops.auto_functionalize import (
    AutoFunctionalized,
    AutoFunctionalizedV2,
)
from torch.fx.node import Argument


@torch.library.custom_op(
    "chatterbox_coreai::mutable_slice_update",
    mutates_args=["value"],
)
def mutable_slice_update(
    value: Tensor,
    update: Tensor,
    begin: Tensor,
    end: Tensor,
) -> Tensor:
    begin_parts = torch.split(begin, 1, dim=0)
    end_parts = torch.split(end, 1, dim=0)
    slices = tuple(
        slice(start.item(), stop.item())
        for start, stop in zip(begin_parts, end_parts, strict=False)
    )
    value[slices] = update
    return value.clone()


@mutable_slice_update.register_fake
def mutable_slice_update_fake(
    value: Tensor,
    update: Tensor,
    begin: Tensor,
    end: Tensor,
) -> Tensor:
    del update, begin, end
    return torch.empty(value.shape, dtype=value.dtype)


@torch.library.custom_op(
    "chatterbox_coreai::immutable_slice_update",
    mutates_args=[],
)
def immutable_slice_update(
    value: Tensor,
    update: Tensor,
    begin: Tensor,
    end: Tensor,
) -> Tensor:
    result = value.clone()
    result[
        begin[0] : end[0],
        begin[1] : end[1],
        begin[2] : end[2],
        begin[3] : end[3],
        begin[4] : end[4],
    ] = update
    return result


@immutable_slice_update.register_fake
def immutable_slice_update_fake(
    value: Tensor,
    update: Tensor,
    begin: Tensor,
    end: Tensor,
) -> Tensor:
    del update, begin, end
    return torch.empty(value.shape, dtype=value.dtype)


@torch.library.custom_op(
    "chatterbox_coreai::immutable_slice_update_4d",
    mutates_args=[],
)
def immutable_slice_update_4d(
    value: Tensor,
    update: Tensor,
    begin: Tensor,
    end: Tensor,
) -> Tensor:
    result = value.clone()
    result[
        begin[0] : end[0],
        begin[1] : end[1],
        begin[2] : end[2],
        begin[3] : end[3],
    ] = update
    return result


@immutable_slice_update_4d.register_fake
def immutable_slice_update_4d_fake(
    value: Tensor,
    update: Tensor,
    begin: Tensor,
    end: Tensor,
) -> Tensor:
    del update, begin, end
    return torch.empty(value.shape, dtype=value.dtype)


class KVCache:
    def __init__(
        self,
        key_cache: torch.Tensor,
        value_cache: torch.Tensor,
    ) -> None:
        self.key_cache = key_cache
        self.value_cache = value_cache

    def update_and_fetch(
        self,
        layer_index: int,
        offset: int,
        key: torch.Tensor,
        value: torch.Tensor,
        *,
        seq_len: int,
        query_len: int,
    ) -> tuple[torch.Tensor, torch.Tensor]:
        torch._check_is_size(layer_index)
        torch._check_is_size(offset)
        torch._check_is_size(seq_len)
        torch._check_is_size(query_len)

        device = self.key_cache.device
        begin = torch.tensor(
            [layer_index, 0, 0, offset, 0],
            dtype=torch.int32,
            device=device,
        )
        end = torch.tensor(
            [
                layer_index + 1,
                self.key_cache.size(1),
                self.key_cache.size(2),
                offset + key.size(2),
                self.key_cache.size(4),
            ],
            dtype=torch.int32,
            device=device,
        )
        mutable_slice_update(
            self.key_cache,
            key.unsqueeze(0),
            begin,
            end,
        )
        mutable_slice_update(
            self.value_cache,
            value.unsqueeze(0),
            begin,
            end,
        )

        key = self.key_cache.narrow(
            0,
            layer_index,
            1,
        ).narrow(-2, 0, seq_len)
        value = self.value_cache.narrow(
            0,
            layer_index,
            1,
        ).narrow(-2, 0, seq_len)
        return key.squeeze(0), value.squeeze(0)


class ExplicitKVCache:
    def __init__(
        self,
        key_cache: torch.Tensor,
        value_cache: torch.Tensor,
    ) -> None:
        self.key_cache = key_cache
        self.value_cache = value_cache

    def update_and_fetch(
        self,
        layer_index: int,
        offset: int,
        key: torch.Tensor,
        value: torch.Tensor,
        *,
        seq_len: int,
        query_len: int,
    ) -> tuple[torch.Tensor, torch.Tensor]:
        del query_len
        device = self.key_cache.device
        begin = torch.cat(
            (
                torch.tensor(
                    [layer_index, 0, 0],
                    dtype=torch.int32,
                    device=device,
                ),
                torch.scalar_tensor(
                    offset,
                    dtype=torch.int32,
                    device=device,
                ).unsqueeze(0),
                torch.tensor(
                    [0],
                    dtype=torch.int32,
                    device=device,
                ),
            )
        )
        end = torch.cat(
            (
                torch.tensor(
                    [
                        layer_index + 1,
                        self.key_cache.size(1),
                        self.key_cache.size(2),
                    ],
                    dtype=torch.int32,
                    device=device,
                ),
                torch.scalar_tensor(
                    seq_len,
                    dtype=torch.int32,
                    device=device,
                ).unsqueeze(0),
                torch.tensor(
                    [self.key_cache.size(4)],
                    dtype=torch.int32,
                    device=device,
                ),
            )
        )
        self.key_cache = immutable_slice_update(
            self.key_cache,
            key.unsqueeze(0),
            begin,
            end,
        )
        self.value_cache = immutable_slice_update(
            self.value_cache,
            value.unsqueeze(0),
            begin,
            end,
        )

        key = self.key_cache.narrow(
            0,
            layer_index,
            1,
        ).narrow(-2, 0, seq_len)
        value = self.value_cache.narrow(
            0,
            layer_index,
            1,
        ).narrow(-2, 0, seq_len)
        return key.squeeze(0), value.squeeze(0)


class DeltaKVCache:
    def __init__(
        self,
        key_cache: torch.Tensor,
        value_cache: torch.Tensor,
    ) -> None:
        self.key_cache = key_cache
        self.value_cache = value_cache
        self.key_updates: list[torch.Tensor] = []
        self.value_updates: list[torch.Tensor] = []

    def update_and_fetch(
        self,
        layer_index: int,
        offset: int,
        key: torch.Tensor,
        value: torch.Tensor,
        *,
        seq_len: int,
        query_len: int,
    ) -> tuple[torch.Tensor, torch.Tensor]:
        del seq_len, query_len
        cached_key = self.key_cache.narrow(
            0,
            layer_index,
            1,
        ).squeeze(0).narrow(-2, 0, offset)
        cached_value = self.value_cache.narrow(
            0,
            layer_index,
            1,
        ).squeeze(0).narrow(-2, 0, offset)
        self.key_updates.append(key)
        self.value_updates.append(value)
        return (
            torch.cat((cached_key, key), dim=-2),
            torch.cat((cached_value, value), dim=-2),
        )

    def stacked_updates(self) -> tuple[torch.Tensor, torch.Tensor]:
        return (
            torch.stack(self.key_updates, dim=0),
            torch.stack(self.value_updates, dim=0),
        )


class StaticDecodeKVCache:
    def __init__(
        self,
        key_cache: torch.Tensor,
        value_cache: torch.Tensor,
        position: torch.Tensor,
    ) -> None:
        self.key_cache = key_cache
        self.value_cache = value_cache
        self.position = position.to(dtype=torch.int32)
        self.key_updates: list[torch.Tensor] = []
        self.value_updates: list[torch.Tensor] = []
        positions = torch.arange(
            key_cache.shape[-2],
            dtype=torch.int32,
            device=key_cache.device,
        )
        self.attention_mask = (positions <= self.position).reshape(
            1,
            1,
            1,
            -1,
        )

    def update_and_fetch(
        self,
        layer_index: int,
        offset: int,
        key: torch.Tensor,
        value: torch.Tensor,
        *,
        seq_len: int,
        query_len: int,
    ) -> tuple[torch.Tensor, torch.Tensor]:
        del offset, seq_len, query_len
        layer_key = self.key_cache.narrow(
            0,
            layer_index,
            1,
        ).squeeze(0)
        layer_value = self.value_cache.narrow(
            0,
            layer_index,
            1,
        ).squeeze(0)
        device = layer_key.device
        begin = torch.cat(
            (
                torch.tensor([0, 0], dtype=torch.int32, device=device),
                self.position.reshape(1),
                torch.tensor([0], dtype=torch.int32, device=device),
            )
        )
        end = torch.cat(
            (
                torch.tensor(
                    [layer_key.size(0), layer_key.size(1)],
                    dtype=torch.int32,
                    device=device,
                ),
                (self.position + 1).reshape(1),
                torch.tensor(
                    [layer_key.size(3)],
                    dtype=torch.int32,
                    device=device,
                ),
            )
        )
        self.key_updates.append(key)
        self.value_updates.append(value)
        return (
            immutable_slice_update_4d(
                layer_key,
                key,
                begin,
                end,
            ),
            immutable_slice_update_4d(
                layer_value,
                value,
                begin,
                end,
            ),
        )

    def stacked_updates(self) -> tuple[torch.Tensor, torch.Tensor]:
        return (
            torch.stack(self.key_updates, dim=0),
            torch.stack(self.value_updates, dim=0),
        )


def _generated_custom_op_node(
    target: Callable[[torch.Tensor], torch.Tensor],
) -> torch.fx.Node:
    def wrapper(value):
        return target(value)

    traced = torch.fx.symbolic_trace(wrapper)
    for node in traced.graph.nodes:
        if (
            hasattr(node.target, "name")
            and node.target.name() == target._qualname
        ):
            return node
    raise RuntimeError(f"Unable to trace {target}.")


def remove_cache_functionalization(
    program: torch.export.ExportedProgram,
) -> None:
    graph = program.graph_module.graph
    auto_nodes: dict[str, fx.Node] = {}
    for node in graph.nodes:
        if isinstance(
            node.target,
            AutoFunctionalized | AutoFunctionalizedV2,
        ):
            if (
                len(node.args) != 1
                or node.args[0].name()
                != "chatterbox_coreai::mutable_slice_update"
            ):
                raise RuntimeError(
                    f"Unexpected functionalized custom op: {node}"
                )
            auto_nodes[node.name] = node

    getitems: list[fx.Node] = []
    replacements: dict[str, fx.Node] = {}
    auto_replacements: dict[str, fx.Node] = {}
    for node in graph.nodes:
        auto_node = next(
            (
                input_node
                for input_node in node.all_input_nodes
                if input_node.name in auto_nodes
            ),
            None,
        )
        if auto_node is None:
            continue

        if auto_node.name in auto_replacements:
            replacement = auto_replacements[auto_node.name]
        else:
            with graph.inserting_before(node):
                replacement = _generated_custom_op_node(
                    immutable_slice_update
                )
                replacement = graph.node_copy(replacement)
                if isinstance(
                    auto_node.target,
                    AutoFunctionalizedV2,
                ):
                    base_index = auto_node.kwargs["_x_base_index"]
                    replacement.args = (
                        auto_node.kwargs["_all_bases"][base_index],
                        auto_node.kwargs["update"],
                        auto_node.kwargs["begin"],
                        auto_node.kwargs["end"],
                    )
                else:
                    replacement.args = tuple(
                        auto_node.kwargs.values()
                    )
                replacement.meta["val"] = node.meta["val"]
                replacement.meta["nn_module_stack"] = node.meta.get(
                    "nn_module_stack",
                    {},
                )
                replacement.meta["stack_trace"] = node.meta.get(
                    "stack_trace",
                    "",
                )
                replacement.meta["source_fn_stack"] = node.meta.get(
                    "source_fn_stack",
                    [],
                )
                replacement.stack_trace = node.stack_trace
            auto_replacements[auto_node.name] = replacement

        node.replace_all_uses_with(replacement)
        getitems.append(node)
        replacements[node.name] = replacement

    signature_replacements: dict[int, fx.Node] = {}
    for node in getitems:
        graph.erase_node(node)
        for index, specification in enumerate(
            program.graph_signature.output_specs
        ):
            if specification.arg.name == node.name:
                signature_replacements[index] = replacements[node.name]

    for node in auto_nodes.values():
        graph.erase_node(node)

    for index, replacement in signature_replacements.items():
        program.graph_signature.output_specs[index].arg.name = (
            replacement.name
        )

    program.graph_module.recompile()


def _operand(
    values: dict[str, Value],
    node: fx.Node,
    index: int,
    location: Location | None,
) -> Value:
    argument: Argument = node.args[index]
    if isinstance(argument, fx.Node):
        return values[argument.name]
    if isinstance(argument, bool | int | float | Tensor | list):
        data = (
            argument.detach().cpu().numpy()
            if isinstance(argument, Tensor)
            else argument
        )
        return coreai.constant(data, loc=location)
    raise ValueError(f"Unsupported operand {argument!r}.")


def _lower_slice_update(values, node, location):
    value = _operand(values, node, 0, location)
    update = _operand(values, node, 1, location)
    begin = _operand(values, node, 2, location)
    end = _operand(values, node, 3, location)
    return coreai.slice_update(
        value,
        begin,
        end,
        [1] * value.type.rank,
        update,
    )


def _lower_passthrough(values, node, location):
    return _operand(values, node, 0, location)


def register_cache_lowering(converter) -> None:
    converter.register_torch_lowering(
        "chatterbox_coreai::immutable_slice_update.default"
    )(_lower_slice_update)
    converter.register_torch_lowering(
        "chatterbox_coreai::immutable_slice_update_4d.default"
    )(_lower_slice_update)
    converter.register_torch_lowering(
        "CompositeOps::label_tensor_as_input.default"
    )(_lower_passthrough)
    converter.register_torch_lowering(
        "CompositeOps::label_tensor_as_output.default"
    )(_lower_passthrough)
