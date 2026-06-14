import unittest

import torch

from vocoder import (
    CoreAICompatibleVocoder,
    CoreAIFourier,
    create_chatterbox_vocoder,
)


class CoreAIFourierTests(unittest.TestCase):
    def test_stft_matches_torch(self) -> None:
        torch.manual_seed(1)
        fourier = CoreAIFourier()
        waveform = torch.randn(1, 3840)
        real, imaginary = fourier.stft(waveform)
        expected = torch.stft(
            waveform,
            16,
            4,
            16,
            window=torch.hann_window(16),
            return_complex=True,
        )

        self.assertTrue(torch.allclose(real, expected.real, atol=1e-5, rtol=1e-5))
        self.assertTrue(
            torch.allclose(imaginary, expected.imag, atol=1e-5, rtol=1e-5)
        )

    def test_istft_matches_torch(self) -> None:
        torch.manual_seed(2)
        fourier = CoreAIFourier()
        waveform = torch.randn(1, 3840)
        spectrum = torch.stft(
            waveform,
            16,
            4,
            16,
            window=torch.hann_window(16),
            return_complex=True,
        )
        actual = fourier.istft(spectrum.real, spectrum.imag)
        expected = torch.istft(
            spectrum,
            16,
            4,
            16,
            window=torch.hann_window(16),
        ).unsqueeze(1)

        self.assertTrue(torch.allclose(actual, expected, atol=2e-6, rtol=1e-5))


class CoreAICompatibleVocoderTests(unittest.TestCase):
    def test_decode_matches_chatterbox(self) -> None:
        torch.manual_seed(3)
        vocoder = create_chatterbox_vocoder().eval()
        model = CoreAICompatibleVocoder(vocoder).eval()
        speech_feat = torch.randn(1, 80, 8)
        source = torch.randn(1, 1, 3840)

        with torch.inference_mode():
            expected = vocoder.decode(speech_feat, source)
            actual = model.decode(speech_feat, source)

        self.assertTrue(torch.allclose(actual, expected, atol=3e-6, rtol=1e-5))


if __name__ == "__main__":
    unittest.main()
