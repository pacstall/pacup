<p align="center"><img alt="logo" src="https://raw.githubusercontent.com/pacstall/pacup/master/imgs/logo.png"></p>
<h1 align="center">Pacup</h1>
<p align="center">
  <a href="https://www.perl.org/"><img alt="Perl" src="https://img.shields.io/badge/language-perl_5-306998?logo=perl&logoColor=white&style=for-the-badge"></a>
  <a href="https://github.com/psf/black"><img alt="Code style: black" src="https://img.shields.io/badge/code%20style-black-black?style=for-the-badge"/></a>
  <a href="https://www.codacy.com/gh/pacstall/pacup/dashboard?utm_source=github.com&amp;utm_medium=referral&amp;utm_content=pacstall/pacup&amp;utm_campaign=Badge_Grade"><img alt="Codacy: grade" src="https://img.shields.io/codacy/grade/4b1365e6f7d2474283243f62b2c5973d?label=Codacy&logo=codacy&style=for-the-badge"></a>
<p/>
<p align="center">
  <!-- Social -->
  <a href="https://discord.gg/yzrjXJV6K8"><img alt="join discord" src="https://img.shields.io/discord/839818021207801878?color=5865F2&label=Discord&logo=discord&logoColor=FFFFFF&style=for-the-badge"></a>
  <a href="https://reddit.com/r/pacstall"><img src="https://img.shields.io/reddit/subreddit-subscribers/pacstall?label=Reddit&color=FF4301&style=for-the-badge&logo=reddit&logoColor=FFFFFF" loading="lazy"></a>
  <a href="https://social.linux.pizza/web/@pacstall"><img alt="Mastodon Follow" src="https://img.shields.io/mastodon/follow/107278715447740005?color=3088d4&domain=https%3A%2F%2Fsocial.linux.pizza&label=Mastodon&logo=mastodon&logoColor=white&style=for-the-badge" loading="lazy"></a>
  <a href="https://matrix.to/#/#pacstall:matrix.org"><img alt="join matrix" src="https://img.shields.io/matrix/pacstall:matrix.org?color=888888&label=Matrix&logo=Matrix&style=for-the-badge"></a>
<p/>

## What is this?

Pacup (**Pac**script **Up**dater) is a maintainer helper tool to help
maintainers update their pacscripts. It semi-automates the tedious task of
updating pacscripts, and aims to make it a fun process for the maintainer!
Originally written in Python, now in Perl.

## Installation

To install the latest release run:

```console
$ pacstall -I pacup-bin # unreleased
```

To install the latest development build run:

```console
$ pacstall -I pacup-git # unreleased
```

or

```console
$ git clone https://github.com/pacstall/pacup.pl
$ cd pacup.pl
$ perl Makefile.PL
$ sudo make install
```

To develop in a `nix` shell run:
```console
$ elsie put something here

```



## Usage

```console
USAGE: pacup [OPTIONS] PACSCRIPTS...

OPTIONS:
    -v, --version
        Print version information and exit.

    -h, -?, --help
        Print this help message and exit.

    -r, --show-repology
        Print the parsed repology data and exit.

    -s, --ship
        Create a new branch and push the changes to git.

    -o, --origin-remote
        Specify the remote repository. Default is 'origin'.

    -c, --custom-version
        Set a custom version for the package to fetch, instead of querying
        Repology.

    -p, --push-force
        Force push to the branch, overwriting any existing one.
```

You can get this help text by running `pacup --help`.

You should visit our [wiki](https://github.com/pacstall/pacup/wiki/Wiki), for
more information on how to use the `repology` key.

## How does it work?

Suppose `foo.pacscript` is outdated.

On running `pacup foo.pacscript` Pacup will parse the pacscript's variables,
then it compiles a list of filters specified in the `repology` variable in the
pacscript. Then it queries the [Repology API](https://repology.org/api) to get
all the repositories which have packaged that package. After which it applies
the filter to the response, and from the filtrate it considers the most common
version to be the latest.

Then it replaces all occurrences of the previous `version`'s value in the `url`
with the latest one placeholder's value with the latest version, and downloads
the new package, and generates it's hash.

Then writes the edited pacscript and installs it with
[Pacstall](https://github.com/pacstall/pacstall), after installation it asks
the user to confirm that the installed package works. On approval the pacscript
is considered successfully upgraded and the program ends.

## Caveats

* Does not work with `-git` pacscripts as those pacscripts are auto updating.
* Doesn't work if a pacscript doesn't have an equivalent
  [Repology](https://repology.org/) package.

## Stats

<p align="center"><img alt="Repobeats analytics image" src="https://repobeats.axiom.co/api/embed/80bc45a6d65fbfb43905aa22b3950badc09edd97.svg" /></p>

## License

```monospace
    ____             __  __
   / __ \____ ______/ / / /___
  / /_/ / __ `/ ___/ / / / __ \
 / ____/ /_/ / /__/ /_/ / /_/ /
/_/    \__,_/\___/\____/ .___/
                      /_/

Copyright (C) 2022-present

This file is part of PacUp

PacUp is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

PacUp is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with PacUp.  If not, see <https://www.gnu.org/licenses/>.
```
