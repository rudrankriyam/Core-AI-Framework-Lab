import unittest

import torch

from chatterbox.models.s3gen.xvector import CAMLayer, CAMPPlus
from chatterbox.models.voice_encoder.voice_encoder import VoiceEncoder
from encoders import (
    CoreAICompatibleVoiceEncoder,
    CoreAIStatsPool,
    _single_segment_pooling,
    replace_batch_norm1d_modules,
)
from vocoder import replace_conv1d_modules


class VoiceEncoderTests(unittest.TestCase):
    def test_compatible_forward_matches_chatterbox(self) -> None:
        torch.manual_seed(10)
        source = VoiceEncoder().eval()
        model = CoreAICompatibleVoiceEncoder(source).eval()
        mels = torch.rand(1, 160, 40)

        with torch.inference_mode():
            expected = source(mels)
            actual = model(mels)

        self.assertTrue(torch.equal(actual, expected))


class SpeakerEncoderTests(unittest.TestCase):
    def test_compatible_pooling_matches_single_segment_campplus(self) -> None:
        torch.manual_seed(11)
        source = CAMPPlus(memory_efficient=False).eval()
        model = CAMPPlus(memory_efficient=False).eval()
        model.load_state_dict(source.state_dict(), strict=True)
        model.xvector._modules["stats"] = CoreAIStatsPool()
        for module in model.modules():
            if isinstance(module, CAMLayer):
                module.seg_pooling = _single_segment_pooling.__get__(module)
        replace_batch_norm1d_modules(model)
        replace_conv1d_modules(model)

        fbank = torch.randn(1, 200, 80)
        with torch.inference_mode():
            expected = source(fbank)
            actual = model(fbank)

        self.assertTrue(torch.allclose(actual, expected, atol=4e-6, rtol=1e-5))


if __name__ == "__main__":
    unittest.main()
