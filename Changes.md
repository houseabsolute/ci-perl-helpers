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
