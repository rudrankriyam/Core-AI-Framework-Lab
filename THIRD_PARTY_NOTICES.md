# Third-Party Notices

## Apple Core AI Models

Core AI Lab depends on the `CoreAIObjectDetection` product from
[apple/coreai-models](https://github.com/apple/coreai-models), pinned to
revision `e358c8435679c904687f8070eb95150e36e4b76d`.

Copyright 2026 Apple Inc.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice,
   this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.
3. Neither the name of the copyright holder nor the names of its contributors
   may be used to endorse or promote products derived from this software
   without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

## Model weights

No Apple catalog model weights are redistributed by this repository. Assets
exported by users retain their upstream licenses and access terms. The verified
`hustvl/yolos-tiny` example reports Apache-2.0 metadata.

## CAM++ speaker embedding

`Conversion/Diarization/model.py` adapts the CAM++ architecture from
[modelscope/3D-Speaker](https://github.com/modelscope/3D-Speaker).

Copyright 3D-Speaker. Licensed under the Apache License, Version 2.0. The
adapted file identifies the converter-specific modifications. A copy of the
license is provided at
`Conversion/Diarization/LICENSES/Apache-2.0.txt`.

The conversion recipe downloads `funasr/campplus` at immutable revision
`e4b6ede7ce16997aff4ae69fbca1f0175e2afede`. Its official model card identifies
the checkpoint as Apache-2.0. The checkpoint and generated Core AI assets are
not redistributed by this repository.
