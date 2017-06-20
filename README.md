# AssetsCodeGenerator
Converting images folder to Images.xcassets and corresponding swift code.
Image file names must end with scale, like ic_jike@2x.png.

### Usage
1. To generate Images.xcassets and code from given images folder, run:

```
swift GenerateAssetsAndCode.swift -i Images -assetsOutput Output/Images.xcassets -codeOutput Output
```

2. Drag Images.xcassets and R.generated.swift to your project
3. In your code:

```Swift
let imageView = UIImageView(image: R.images.ic_jike)
```
