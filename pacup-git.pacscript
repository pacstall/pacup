name="pacup-git"
gives="pacup.pl"
pkgver="3.0.0"
pkgdesc="Next-gen rewrite of Pacup"
depends=(
  'libdata-compare-perl'
  'libfile-chdir-perl'
  'libipc-system-simple-perl'
  'libjson-perl'
  'libwww-perl'
  'liblist-moreutils-perl'
)
replace=(
  "${gives}"
  "${gives}-bin"
  "${gives}-git"
)
url="https://github.com/pacstall/${gives}.git"
maintainer="vigress8 <vig@disroot.org>"

build() {
  perl Makefile.PL
  make -j"${NCPU}"
}

package() {
  sudo make install DESTDIR="${pkgdir}"
}
