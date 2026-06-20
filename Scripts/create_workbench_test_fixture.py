#!/usr/bin/env python3
"""Generate the tiny deterministic Core AI asset used by workbench tests."""

from pathlib import Path
import shutil

import torch
from coreai.runtime import AIModelAssetMetadata
from coreai_torch import TorchConverter, get_decomp_table


class ScaleAndBias(torch.nn.Module):
    def forward(self, values):
        return values * 2.0 + 1.0


class IncrementTokens(torch.nn.Module):
    def forward(self, tokens):
        return tokens + 1


def exported(module: torch.nn.Module, example: torch.Tensor):
    program = torch.export.export(module.eval(), args=(example,))
    return program.run_decompositions(get_decomp_table())


def main() -> None:
    repository = Path(__file__).resolve().parents[1]
    output = repository / "CoreAILabTests/Fixtures/CoreAILabTensorFixture.aimodel"
    if output.exists():
        shutil.rmtree(output)

    converter = TorchConverter()
    converter.add_exported_program(
        exported_program=exported(
            ScaleAndBias(),
            torch.zeros(1, 4, dtype=torch.float32),
        ),
        input_names=["values"],
        output_names=["scaled_values"],
        entrypoint_name="scale_and_bias",
    )
    converter.add_exported_program(
        exported_program=exported(
            IncrementTokens(),
            torch.zeros(1, 4, dtype=torch.int32),
        ),
        input_names=["tokens"],
        output_names=["incremented_tokens"],
        entrypoint_name="increment_tokens",
    )

    program = converter.to_coreai()
    program.optimize()
    metadata = AIModelAssetMetadata()
    metadata.author = "Core AI Lab"
    metadata.license = "MIT"
    metadata.model_description = (
        "Tiny deterministic tensor fixture for the generic function workbench."
    )
    metadata.creation_date = 1_718_928_000
    output.parent.mkdir(parents=True, exist_ok=True)
    program.save_asset(output, metadata)
    print(output)


if __name__ == "__main__":
    main()
