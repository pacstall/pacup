pkgname="pacup.pl-git"
gives="pacup.pl"
pkgver="20240412"
pkgdesc="Next-gen rewrite of Pacup"
depends=(
  'libdata-compare-perl'
  'libfile-chdir-perl'
  'libipc-system-simple-perl'
  'libjson-perl'
  'libwww-perl'
)
source=("https://github.com/vigress8/pacup.pl.git")
maintainer=("vigress8 <vig@disroot.org>")

package() {
  cd "${gives}"
  perl Makefile.PL
  make install DESTDIR="${pkgdir}"
}
