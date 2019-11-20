## 0.0.5 2019-11-20

* On macOS and Windows the tools are now installed by referencing the
  repository resource. This guarantees that you get the version of the tools
  that corresponds to that commit in this repo. The previous method of packing
  the tools as a base64 blob required a manual step to ensure that the tools
  were up to date. Fixes #7.

* Only pass absolute paths to `prove` when running coverage tests (which are
  only done on Linux). Passing absolute paths causes issues on Windows.

* Fixed breakage introduced in 0.0.4 for Windows builds. The step to run tests
  would always fail to execute prove. Reported by xenu. Fixes #8.


## 0.0.4 2019-11-19

* Updated the base64 version of the tools (used on macOS and Windows) with
  changes in the last version.


## 0.0.3 2019-11-19

* When running `prove` we now pass the test dirs as absolute paths. This
  allows tests to use `FindBin` safely (to access `t/lib` for example) even if
  the current working directory changes before the test code is run. This
  happens with `Devel::Cover` when the `-dir` flag is passed to it. See
  https://github.com/pjcj/Devel--Cover/issues/247 for my issue report about
  this.


## 0.0.2 2019-11-19

* Added a step to install dynamic prereqs. These prereqs will never be cached,
  but I'm assuming that most prereqs will be static.


## 0.0.1 2019-11-18

* First release upon an unsuspecting world.
