name="pacup"
pkgver="3.0.0"
pkgdesc="Help maintainers update pacscripts (next-gen Perl rewrite)"
depends=(
  'libdata-compare-perl'
  'libfile-chdir-perl'
  'libipc-system-simple-perl'
  'libjson-perl'
  'libwww-perl'
  'liblist-moreutils-perl'
  'libterm-progressbar-perl'
)
replace=(
  "${name}"
  "${name}.pl"
  "${name}.py"
  "${name}-bin"
  "${name}-git"
)
url="https://github.com/pacstall/${name}/archive/refs/tags/${pkgver}.zip"
maintainer="vigress8 <vig@disroot.org>"

build() {
  perl Makefile.PL
  make -j"${NCPU}"
}

package() {
  sudo make install DESTDIR="${pkgdir}"
}
