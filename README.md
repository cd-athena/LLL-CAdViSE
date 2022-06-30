[![Docker Image CI](https://github.com/cd-athena/LLL-CAdViSE/actions/workflows/clientDockerImage.yml/badge.svg?branch=master&event=push)](https://github.com/cd-athena/LLL-CAdViSE/actions/workflows/clientDockerImage.yml)

## LLL-CAdViSE: Live Low Latency Cloud-based Adaptive Video Streaming Evaluation Framework for the Automated Testing of Media Players
This Adaptive Bitrate (ABR) testbed is based on [CAdViSE](https://github.com/cd-athena/CAdViSE).

- A configurable live media encoder (with different codecs)
- Video and audio content generator (no dataset is required)
- Flexible bitrate ladder for each experiment 
- A configurable live media packager 
- Simulates CDN CMAF chunks delivery
- Run multiple clients of the same player [32xdashjs]
- Realistic network profiles
- Low Latency parameters in encoder/packager
- Tests Low Latency ABR algorithms
- Low-weight for deployment on cloud

#### Running on AWS cloud
```
./run.sh --players 2xdashjs --shaper network/network0.json --awsKey ppt-key
```