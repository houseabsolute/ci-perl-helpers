## 0.0.13 2019-12-25

* The `image_version` change in the last release was not done properly. It got
  the branch name from the repo that was using the helpers, not from the
  helpers themselves. But it did work for _tags_.

* Fixed an issue where variables set using `##vso` log output would end up
  being set twice. If the bash code in question did a `set -x`, then the log
  output would come out twice, leading to much confusion.


## 0.0.12 2019-12-23

* Docker images are now tagged with multiple tags at once. If we push a new
  commit to master and it's tagged with a version number, we end up with both
  a "-master" and "-vX.Y.Z" tag.

* The `image_version` parameter is now optional for all stage templates. If it
  is not passed then the version will be picked based on the commit that is
  used for the `ci-perl-helpers` repo. If the commit matches a version tag,
  then that is used as the `image_version`. Otherwise the branch name is used.


## 0.0.11 2019-12-22

* In v0.0.8, I changed the naming of the Docker containers and forgot to
  change it in the templates.


## 0.0.10 2019-12-21

* Fixed Windows builds. These were broken by a change in a recent berrybrew
  release, but hard-coding a version of Perl to use is pretty sloppy. We now
  pick the latest available version from berrybrew (which still makes some
  assumptions about berrybrew that may break in the future).


## 0.0.9 2019-12-14

* Docker images are now created in Azure after each push and tagged
  appropriately. In addition, images are created for every patch release of
  Perl starting with 5.12, instead of just the last patch release of the
  series.


## 0.0.8 2019-11-29

* All of the Docker images now include a tag from this repo, so I can push new
  images without risk of breaking existing builds.


## 0.0.7 2019-11-29

* Add a title to the published test results. The title is the same as the
  job's title.


## 0.0.6 2019-11-23

* When calling `tap2junit` we make sure not to exceed a command length of
  5,000 characters. On Windows very long commands fail. Despite `getconf
  ARG_MAX` in bash on Windows saying that the limit is 32,000, experimentation
  showed me that the limit is somewhere around 5,000. This fixes testing when
  you have a very large number of test files.

* Ignore the checksum when installing berrybrew on Windows using
  chocolatey. This is necessary because of an issue with the install script
  for berrybrew. See https://github.com/camilohe/berrybrew.install/issues/1
  for details. Once that is fixed we will go back to respecting the checksum,
  but for now this is necessary to keep Windows builds working.

* Add support for partitioning tests when running coverage tests. Running
  tests under Devel::Cover can be _much_ slower than normal, and large test
  suites (for example Moose's) can easily take more than the 1 hour limit per
  job imposed by Azure. See the `README.md` file for documentation on this
  feature.

* The raw output from `Devel::Cover` is no longer published as a build
  artifact automatically. You need to enable this with the
  `publish_coverage_artifact` parameter. This was done because some test
  suites output enormous number of files which take a very long time to
  publish. In addition, coverage artifacts will only be published when the job
  succeeds (meaning all tests passed).

* The step to publish coverage to codecov.io will now only be run when tests
  pass.


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
