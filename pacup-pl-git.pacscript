pkgname="pacup-pl-git"
pkgver="20240404"
pkgdesc="Next-gen rewrite of Pacup"
depends=(
  'libfile-chdir-perl'
  'libipc-system-simple-perl'
  'libjson-perl'
)
source=("https://github.com/vigress8/pacup.pl.git")
maintainer=("vigress8 <vig@disroot.org>")

package() {
  install -Dm755 pacup.pl -t "$pkgdir/usr/bin"
}