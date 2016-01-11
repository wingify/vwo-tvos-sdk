# vwo-tvos-sdk
VWO A/B Testing SDK for tvOS

Either the raw code can be used or framework can be used.

Instructions for using Framework in your own profile file.
* Add the Framework in "Embedded Binaries" under Target of Project file.
* Under Build Settings of Target, mark "Embedded Content Contains Swift Code" YES
* Add [this script](https://github.com/realm/realm-cocoa/blob/d59c86f11525f346c8e8db277fdbf2d9ff990d98/scripts/strip-frameworks.sh) in "Run Script" under "Build Phases" because of [this issue](http://stackoverflow.com/questions/29634466/how-to-export-fat-cocoa-touch-framework-for-simulator-and-device)

## License

By using this SDK, you agree to abide by the [VWO Terms & Conditions](https://vwo.com/terms-conditions).
