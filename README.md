# AR Stack

![demo](demo.gif)

## About
This app brings the popular game [Stack](https://apps.apple.com/us/app/stack/id1080487957) in the real world with Augmented Reality. If you like this app or found it useful, I would appreciate if you starred it or even shared it with your friends. I don't expect to work on this too much more, as it was my first venture into AR and I came back to it because I had some free time.

## Acknowledgments
The bulk of this code was written by [Xander Xu](https://github.com/XanderXu/ARStack) in his tutorial. Because the Apache-2.0 license was included, I have taken the code and improved upon it. The basic functionality and logic is not mine, however, so most of the credit should go to him. If you would like to modify this app further, you are more than welcome to, as the same license is included, as long as all the rules regarding copyright, distribution, etc are followed.

## Changes
* The app shows you all detected planes and allows you to move the game location to within any of them.
* The blocks now cycle through a nice rainbow of pastel colors as opposed to being seemingly random. 
* The session information label, debug options, and FPS bar have been hidden under the `Debug` button.
* The AR Coaching Overlay view has been added to aid with establishing the scene instead.
* A slight shadow has been added to the text so it is hopefully easier to see.
* The `GameScene` was raised so the game never goes below the plane you are playing it on.
* In addition to sounds, there are also some slight haptics that you can feel.
* Person segmentation has been added while a game is active so you hand could be occluded.
* The app now displays your high score in the top left. Can you beat my record of 51?
* There is now an app icon, which I might have taken from the original Stack game.
* The launch screen is a little bit nicer and the main screen takes up the full screen.
* The app's settings have been update according to Xcode's recommendations.
* The code itself has be commented fully with the help of ChatGPT, and `MARK` lines label each section.

## Installation
1. Clone this repository or download it as a zip folder and uncompress it.
2. Open up the `.xcodeproj` file, which should automatically launch Xcode.
3. You might need to change the signing of the app from the current one.
4. Click the `Run` button near the top left of Xcode to build and install.

#### Prerequisites
Hopefully this goes without saying, but you need Xcode, which is only available on Macs.

#### Notes
You must connect a physical device to your computer to run this, as a simulator does not support AR tracking. <br>
The device must be either an iPhone or iPad running iOS 16.0 or newer.

## SDKs
* [ARKit](https://developer.apple.com/documentation/arkit/) - Integrate hardware sensing features to produce augmented reality apps and games.
* [SceneKit](https://developer.apple.com/documentation/scenekit/) - Create 3D games and add 3D content to apps using high-level scene descriptions.
* [UIKit](https://developer.apple.com/documentation/uikit/) - Construct and manage a graphical, event-driven user interface for your iOS, iPadOS, or tvOS app.
* [Swift](https://developer.apple.com/swift/) - A powerful and intuitive programming language for all Apple platforms.

## Bugs
If you find any, feel free to open up a new issue or even better, create a pull request fixing it.

#### Known
- [ ] The game may stutter upon stacking the first block.
- [ ] Sounds are sometimes unreliable; partially solved using haptics.
- [ ] The session information label may say that no planes have been detected even though some have been because the `trackingState` is update asynchronously from plane detection when `Debug` is toggled on.
- [ ] If the app goes into a degraded tracking state after the `baseNode` has been added but before a game has started, it along with any other `planeNodes` will disappear. Once the tracking state becomes normal again, new `planeNodes` will spawn, but the `baseNode` will not be placed automatically. A workaround is to just hit the `Reset` button.

#### Resolved
- [x] The AR Coaching Overlay might not have taken up the full screen on newer iPhones.

## Contributors
Sachin Agrawal: I'm a self-taught programmer who knows many languages and I'm into app, game, and web development. For more information, check out my website or Github profile. If you would like to contact me, my email is [github@sachin.email](mailto:github@sachin.email).

## License
This package is licensed under the [Apache License](LICENSE.txt).

```
Copyright 2023-2024 Sachin Agrawal

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```
