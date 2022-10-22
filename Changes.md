## 0.2.3 2022-10-22

* Fixed a bug in the templates where they would always attempt to call
  `./dev-bin/install-xt-tools.sh` even if it didn't exist.


## 0.2.2 2022-08-20

* All Azure VMs now use Ubuntu 20.04 instead of 18.04.


## 0.2.1 2022-07-17

* Fix an issue with generating the test matrix that seems to have popped up
  recently. The system perl used to be able to fetch `https` URLs, presumably
  because it had `IO::Socket::SSL` available, but this appears to no longer be
  the case.


## 0.2.0 2022-04-25

* The base image for all Docker images is now Ubuntu 20.04 instead of 18.04.


## 0.1.12 2021-11-24

* Fixed package installs under Linux. The helpers now run `apt-get update`
  before attempting to `apt-get install` anything.

* Removed the Kritika coverage option. This service appears to be defunct.


## 0.1.11 2021-02-06

* Make sure the test_xt parameter is passed through to all relevant templates,
  and make it default to false.


## 0.1.10 2021-02-06

* The last release accidentally disabled running tests except for jobs where
  `test_xt` was true.


## 0.1.9 2021-01-08

* If the distro name starts with "Dist-Zilla", then the distro's lib dir will
  be included in `@INC` (via `dzil -I lib`) when running `dzil build.


## 0.1.8 2021-01-08

* If a distro has a script named `dev-bin/install-xt-tools.sh` we now run this
  before running xt tests.


## 0.1.7 2020-12-04

* Fixed a bug where we could not figure out what Docker image version to
  use. The method we used to use stopped working at some point, so I had to
  find a new creative way to find the corresponding branch in a detached git
  checkout.


## 0.1.6 2020-04-19

* Fixed a bug that caused macOS builds to fail semi-randomly (after the first
  build). The issue is that the macOS workspace directory can change between
  runs. We were caching & restoring directory trees under this workspace
  directory, so if the cache restore put the restored tree in the wrong
  workspace directory, failures ensured. [I reported this MS via their
  community
  forum](https://developercommunity.visualstudio.com/content/problem/997095/workspace-directory-for-macos-hosted-agents-change.html).


## 0.1.5 2020-04-10

* Fixed bugs that prevented testing of dists that used `Module::Build` or
  `ExtUtils::MakeMaker` (as opposed to `Dist::Zilla`).


## 0.1.4 2020-01-26

* Fix failure to run `curl` with `--compressed` flag on Windows.

* Fix issues caused by changes to the default `$PATH` on Windows. See
  https://github.com/actions/virtual-environments/pull/211/ for what
  changed. I suspect this PR will be reverted but it doesn't hurt to
  explicitly add the paths we care about.


## 0.1.3 2020-01-18

* If `test_xt` was true, then all jobs with the most recent stable Perl would
  run extended tests, including jobs running with coverage enabled. Now only
  one such job (without coverage or threads) will run these tests.


## 0.1.2 2020-01-05

* All test templates now accept an `extra_prereqs` parameter. This is list of
  additional Perl packages to install before running the tests.

* Fix our use of `brew` in the macOS template. We cannot call it with `sudo`.


## 0.1.1 2020-01-02

* When generating the test matrix we skip any version of Perl which was
  released after the commit of this repo that is being used. Otherwise we
  could ask for a Perl version for which there is no corresponding Docker
  image.


## 0.1.0 2020-01-01

**Old configurations will not work with this release. Please see the
[README.md](README.md) for details on how to configure these helpers for your
project.**

* The single test stage has been split up into three stages, one for each of
  Linux, macOS, and Windows.

* You can easily configure whatever set of Perl versions you want on each OS,
  though Windows is still limited to Perl versions provided by
  [Berrybrew](https://github.com/stevieb9/berrybrew). In addition, you can now
  set `test_xt` and coverage parameters for all operating system, not just
  Linux,

* You can run coverage testing with a Perl version of your choice. By default
  this will be done with the most recent stable release that you are testing
  with.

* All test stages now allow you to specify an arbitrary list of packages to be
  installed using apt, Brew, or Chocolatey, as appropriate.

* You can now pass an arbitrary list of steps to be executed both before and
  after the steps executed by the test stage in the job that runs tests.


## 0.0.15 2019-12-27

* Separated the creation of the coverage report from running tests in the
  Azure Pipeline steps.


## 0.0.14 2019-12-26

* Pin our berrybrew install to 1.29. The new 1.30 seems to have some issues
  (see https://github.com/stevieb9/berrybrew/issues/237) and broke all my
  pipeline builds on Windows. Pinning will let us upgrade on our own schedule.


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
