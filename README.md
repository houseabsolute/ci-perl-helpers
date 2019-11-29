# Perl Helper Tools for Continuous Integration

This repo contains a set of tools and CI templates designed to make it easy to
test Perl projects with multiple versions of Perl across Linux, macOS, and
Windows.

## Alpha Warning

**Warning. This stuff is all still pretty new and I may break it while working
on it, I may break compatibility with any given commit, and I may brake for
squirrels in the road. You have been warned.**

## Creating a Service Connection

In order to use these templates in your pipelines you must create a "Service
Connection" for your Azure project. Fortunately this is only needed once per
Azure project, and a single project can contain many pipelines, each of which
corresponds to a single code project (GitHub repo, Subversion repo, etc.).

* Go to https://dev.azure.com/
* Click on the project that contains (or will contain) the pipelines which will use these templates.
* Click on the gear icon in the lower left.
* Click on "Service Connections".
* Select "New service connection", then "GitHub".
* You will be prompted for a connection name. It does not matter what you
  choose, but for simplicity I recommend you use
  `houseabsolute/ci-perl-helpers`.
* Click on "Authorize".
  * You may be prompted to log in to GitHub and/or to allow a third party
    application to access GitHub on your behalf. You will need to allow this,
    obviously.

If you have multiple Azure projects you will need to do this once per project.

## Quick Start

Put this in your `azure-pipelines.yml` file:

```yaml
resources:
  repositories:
    - repository: ci-perl-helpers
      type: github
      name: houseabsolute/ci-perl-helpers
      endpoint: houseabsolute/ci-perl-helpers

stages:
  - template: templates/build.yml@ci-perl-helpers
  - template: templates/test.yml@ci-perl-helpers
```

This will test your Perl project in the following scenarios:

* On Windows, using the latest stable version of Perl available via
  [Berrybrew](https://github.com/stevieb9/berrybrew).
* On macOS, using the latest stable version of Perl.
* On Linux with the last stable release of each major Perl version starting
  from 5.8.9 up to the newest stable release (5.30.1 at the time this was
  written).
  * The most recent stable release will install all of your `develop` phase
    dependencies and run tests with the following environment variables set to
    a true value:
      * `AUTOMATED_TESTING`
      * `AUTHOR_TESTING`
      * `EXTENDED_TESTING`
      * `RELEASE_TESTING`
* On Linux with the latest dev release of Perl (5.31.6 at the time this was
  written). If tests fail when `prove` is run then your pipeline will still
  pass, but a failure to compile your code will cause the pipeline to fail.
* On Linux with the current contents of the `blead` branch of the
  [github.com/Perl/perl5 repo](https://github.com/Perl/perl5). If tests fail
  when `prove` is run then your pipeline will still pass, but a failure to
  compile your code will cause the pipeline to fail.

## Pinning a Helpers Version

If you do not specify a `ref` when referring to this repo, your build will
always pull the latest version of this project's templates. To pin your
project to a specific verson of these templates, add a `ref` key:

```yaml
resources:
  repositories:
    - repository: ci-perl-helpers
      type: github
      name: houseabsolute/ci-perl-helpers
      ref: refs/tags/v0.0.1
      endpoint: houseabsolute/ci-perl-helpers
```

## Customizing Your Build

There are a number of knobs you can turn to tweak exactly what builds happen.

The Build stage template, `build.yml`, takes the following parameters:

* `cache_key` - If you set this to a string it will be used as part of the
  cache key for the Perl installation used by this stage. Every time you
  change this key you will invalidate the old cache. In most cases you should
  not need to change this for the Build stage, but if your build fails in a
  confusing way you can try setting this to see if that fixes the problem. If
  it does, just leave the new key in place and the next build will use the new
  cache.
* `debug` - If you set this to a true value then the helper tools will spew
  out a lot more debugging information. Please set this to true and do a build
  before reporting issues with these tools. That way I can look at your failed
  build and have a better sense of what went wrong.

The Test stage template, `test.yml`, takes the following parameters:

* `cache_key` - If you set this to a string it will be used as part of the
  cache key for the Perl installation used by this stage. Every time you
  change this key you will invalidate the old cache. Unlike with the Build
  stage, you may find yourself wanting to change this regularly. In
  particular, your installed dependencies are cached, so you may want to
  change this key whenever your project's dependencies change. This will
  ensure that your tests are run against a Perl that only includes the
  dependencies you explicitly specified.
* `debug` - If you set this to a true value then the helper tools will spew
  out a lot more debugging information. Please set this to true and do a build
  before reporting issues with these tools. That way I can look at your failed
  build and have a better sense of what went wrong.
* `coverage` - By default the Test stage does not do any coverage tests. You
  can use this parameter to enable a coverage test with the latest stable
  release of Perl. The following values are accepted:
  * `html` - Generates a report as a set of HTMl files.
  * `clover` - Generates a report in the format expected by the [Atlassian
    Clover software](https://www.atlassian.com/software/clover).
  * `codecov` - Uploads coverage data to
    [codecov.io](https://codecov.io/). You must also set `CODECOV_TOKEN` as a
    [pipeline
    variable](https://docs.microsoft.com/en-us/azure/devops/pipelines/process/variables). You
    almost certainly want to make this value secret. If your repository
    contains a `.codecov.yml` file then this will be used when uploading the
    report.
  * `coveralls` - Uploads coverage data to
    [coveralls.io](https://coveralls.io/). You must also set `COVERALLS_TOKEN` as a
    [pipeline
    variable](https://docs.microsoft.com/en-us/azure/devops/pipelines/process/variables). You
    almost certainly want to make this value secret.
  * `kritika` - Uploads coverage data to
    [kritika.io](https://kritika.io/). You must also set `KRITIKA_TOKEN` as a
    [pipeline
    variable](https://docs.microsoft.com/en-us/azure/devops/pipelines/process/variables). You
    almost certainly want to make this value secret.
  * `sonarqube` - Generates a report in the format expected by
    [SonarQube](https://www.sonarqube.org/). See [the
    `Devel::Cover::Report::SonarGeneric`
    docs](https://metacpan.org/pod/Devel::Cover::Report::SonarGeneric) for
    details on how to have this automatically uploaded to SonarQube.
  * `coverage_partitions` - Running tests under `Devel::Cover` can be _much_
    slower than running them normally. You can partition coverage testing into
    an arbitrary number of partitions to make this faster. Because of
    limitations in Azure, you must set this parameter to **an array**
    containing the list of partition numbers. So for four partitions you would
    write `coverage_partitions: [1, 2, 3, 4]`.
  * `publish_coverage_artifact` - If this is a true value then the raw output
    from `Devel::Cover` will be published as a build artifact. This is
    disabled by default because some test suites generate incredibly enormous
    numbers of coverage files, which take a very long time to publish.
  * `include_*` - There are a number of parameters to control exactly what
    Perls and what platforms are tested. All of these are `true` by default.
    * `include_5_30`
    * `include_5_28`
    * `include_5_26`
    * `include_5_24`
    * `include_5_22`
    * `include_5_20`
    * `include_5_18`
    * `include_5_16`
    * `include_5_14`
    * `include_5_12`
    * `include_5_10`
    * `include_5_8`
    * `include_dev`
    * `include_blead`
    * `include_macos`
    * `include_windows`
  * `include_threaded_perls` - By default, tests are only run with an
    unthreaded `perl`. If your code uses threads directly _or_ if your code
    contains XS, you should enable testing with threaded perls as well.

**Note that because of how Azure Pipelines handles parameters, you need to
pass `true` and `false` as strings, not booleans!** For example:

```yaml
  - template: templates/test.yml@ci-perl-helpers
    parameters:
      include_threaded_perls: 'true'
      include_5_8: 'false'
```

## How This Works

These tools consist of a set of Azure Pipeline templates, Perl scripts for
various tasks, and a set of Docker images for Linux testing.

The Docker images contain two versions of Perl, one of which is used to run
the tools and build the distribution, and one of which is used to execute your
package's tests. This is useful for a few reasons. It lets the tools use
modern Perl idioms. It means you can test on older Perls even if your tooling
requires a newer Perl (for example,
[`Dist::Zilla`](https://metacpan.org/pod/Dist::Zilla) requires Perl
5.14.0). It also means that dependencies needed for building, for example
[`Dist::Zilla`](https://metacpan.org/pod/Dist::Zilla) and its dependencies,
are not present when running tests. This means there's a better chance of
discovering missing prereqs.

The Pipeline itself has two stages. The Build stage contains a single
job. This job checks out your source and generates a tarball from it using
your build tooling. The helper tools can detect the use of dzil or minilla,
and will use them when appropriate. Otherwise the tools fall back to using
your `Makefile.PL` or `Build.PL` and executing `make dist` or `./Build
dist`. The resulting tarball is saved as a pipeline artifact.

The test stage contains one or more jobs, each of which tests your
distribution on a single platform and version of Perl. It downloads the
tarball created in the Build stage, extracts this, and then executes it's
`Makefile.PL` or `Build.PL`, as appropriate. The tests are run using
[`prove`](https://metacpan.org/pod/distribution/Test-Harness/bin/prove).

If you asked for coverage testing, then the appropriate
`HARNESS_PERL_SWITCHES` environment variable settings are used to invoke
[`Devel::Cover`](https://metacpan.org/pod/Devel::Cover). All of the coverage
output is saved as a build artifact. Some coverage reporters also upload the
report directly to a code coverage service. Finally, the test output from
`prove` is turned into JUnit XML and uploaded as a set of test results, which
lets you see a more detailed view of test failures in the Azure Pipelines
screen for each CI run.

## Todo Items

See this repository's
[issues](https://github.com/houseabsolute/ci-perl-helpers/issues) for todo
items.

