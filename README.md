[![Client Docker Image CI](https://github.com/cd-athena/LLL-CAdViSE/actions/workflows/clientDockerImage.yml/badge.svg)](https://github.com/cd-athena/LLL-CAdViSE/actions/workflows/clientDockerImage.yml)

## Live Low Latency Cloud-based Adaptive Video Streaming Evaluation (LLL-CAdViSE) framework
This testbed is based on [CAdViSE](https://github.com/cd-athena/CAdViSE).

- Evaluates both MPEG-DASH and HLS
- Video and audio content generator (no dataset is required)
- Configurable live media encoder (with different codecs)
- Configurable bitrate ladder for each experiment
- Configurable live media packager
- Emulates CMAF chunks delivery with CTE
- Evaluates multiple instances of the same or different players (e.g. 120xdashjs)
- Realistic network profiles (LTE or 3G traces)
- Low Latency parameters in encoder/packager (LHLS is experimental)
- Evaluates Low Latency ABR algorithms
- Lightweight mode (up and running in ~55 seconds)
- QoE calculation using ITU-T P.1203 (mode 1)
- Evaluates various significant metrics (stallsDuration, startUpDelay, seekedDuration, qualitySwitches, Bitrate, Latency, PlaybackRate)

#### Running on AWS cloud
```
./run.sh --players 5xdashjs 2xhlsjs 3xdashjsl2a --shaper network/network0.json --awsKey [YOUR-KEY] --withQoE
```