# Copyright 1999-2016 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Id$

# To use you should block the package released from ::gentoo
# 
# In /etc/portage/package.mask add:
# dev-lang/R:0
# 


EAPI=5

inherit bash-completion-r1 autotools eutils flag-o-matic fortran-2 multilib versionator toolchain-funcs

BCP=${PN}-20130129.bash_completion
DESCRIPTION="Language and environment for statistical computing and graphics"
HOMEPAGE="http://www.r-project.org/"
SRC_URI="
	mirror://cran/src/base/R-3/${P}.tar.gz
	https://dev.gentoo.org/~bicatali/distfiles/${BCP}.bz2"

LICENSE="|| ( GPL-2 GPL-3 ) LGPL-2.1"
R_VERSION_MAJOR="$(get_version_component_range 1)"
R_VERSION_MINOR="$(get_version_component_range 1-2)"
R_VERSION_PATCH="$(get_version_component_range 1-3)"
R_PATCHNUM="$(get_version_component_range 3)"

SLOT="${R_VERSION_MINOR}/${R_PATCHNUM}"
KEYWORDS="~amd64 ~hppa ~ia64 ~ppc ~ppc64 ~sparc ~x86 ~x86-fbsd ~amd64-linux ~x86-linux ~x64-macos"
IUSE="blas +bzip2 +cairo doc +icu +java +jpeg lapack +lzma -minimal +nls openmp +pcre +perl +png prefix profile readline static-libs +tiff +tk +X +zlib -static-libs +shared-libs -bash-completion"
REQUIRED_USE="png? ( || ( cairo X ) ) jpeg? ( || ( cairo X ) ) tiff? ( || ( cairo X ) )"
# TODO add use tre for sys-libs/tre


CDEPEND="
	app-text/ghostscript-gpl
	bzip2? ( app-arch/bzip2:0= )
	lzma? ( app-arch/xz-utils:0= )
	pcre? ( >=dev-libs/libpcre-8.35:3= )
	blas? ( virtual/blas:0 )
	|| ( >=sys-apps/coreutils-8.15 sys-freebsd/freebsd-bin app-misc/realpath )
	cairo? ( x11-libs/cairo:0=[X] x11-libs/pango:0= )
	icu? ( dev-libs/icu:= )
	jpeg? ( virtual/jpeg:0 )
	lapack? ( virtual/lapack:0 )
	perl? ( dev-lang/perl )
	png? ( media-libs/libpng:0= )
	readline? ( sys-libs/readline:0= )
	tiff? ( media-libs/tiff:0= )
	tk? ( dev-lang/tk:0= )
	X? ( x11-libs/libXmu:0= x11-misc/xdg-utils )"

DEPEND="${CDEPEND}
	virtual/pkgconfig
	doc? (
		virtual/latex-base
		dev-texlive/texlive-fontsrecommended
	)"

RDEPEND="${CDEPEND}
	zlib? ( || ( <sys-libs/zlib-1.2.5.1-r1:0 >=sys-libs/zlib-1.2.5.1-r2:0[minizip] ) )
	java? ( >=virtual/jre-1.5 )"

RESTRICT="minimal? ( test )"

R_DIR="${EROOT%/}/usr/local/${PN}-${R_VERSION_MINOR}"
PREFIX="${EROOT%/}/usr/local/${PN}-${R_VERSION_MINOR}"

pkg_setup() {
	if use openmp; then
		if [[ $(tc-getCC) == *gcc ]] && ! tc-has-openmp; then
			ewarn "OpenMP is not available in your current selected gcc"
			die "need openmp capable gcc"
		fi
		FORTRAN_NEED_OPENMP=1
	fi
	fortran-2_pkg_setup
	filter-ldflags -Wl,-Bdirect -Bdirect
	# avoid using existing R installation
	unset R_HOME
	# Temporary fix for bug #419761
	if [[ ($(tc-getCC) == *gcc) && ($(gcc-version) == 4.7) ]]; then
		append-flags -fno-ipa-cp-clone
	fi
}

src_prepare() {
	# fix packages.html for doc (gentoo bug #205103)
	sed -i \
		-e "s:../../../library:../../../../$(get_libdir)/R/library:g" \
		src/library/tools/R/Rd.R || die

	# fix Rscript path when installed (gentoo bug #221061)
	sed -i \
		-e "s:-DR_HOME='\"\$(rhome)\"':-DR_HOME='\"${R_DIR}\"':" \
		src/unix/Makefile.in || die "sed unix Makefile failed"

	# fix HTML links to manual (gentoo bug #273957)
	sed -i \
		-e 's:\.\./manual/:manual/:g' \
		$(grep -Flr ../manual/ doc) || die "sed for HTML links failed"

	use lapack && \
		export LAPACK_LIBS="$($(tc-getPKG_CONFIG) --libs lapack)"

	if use X; then
		export R_BROWSER="$(type -p xdg-open)"
		export R_PDFVIEWER="$(type -p xdg-open)"
	fi
	use perl && \
		export PERL5LIB="${S}/share/perl:${PERL5LIB:+:}${PERL5LIB}"

	# don't search /usr/local
	sed -i -e '/FLAGS=.*\/local\//c\: # removed by ebuild' configure.ac || die
	# Fix for Darwin (OS X)
	if use prefix; then
		if [[ ${CHOST} == *-darwin* ]] ; then
			sed -i \
				-e 's:-install_name libR.dylib:-install_name ${libdir}/R/lib/libR.dylib:' \
				-e 's:-install_name libRlapack.dylib:-install_name ${libdir}/R/lib/libRlapack.dylib:' \
				-e 's:-install_name libRblas.dylib:-install_name ${libdir}/R/lib/libRblas.dylib:' \
				-e "/SHLIB_EXT/s/\.so/.dylib/" \
				configure.ac || die
			# sort of "undo" 2.14.1-rmath-shared.patch
			sed -i \
				-e "s:-Wl,-soname=libRmath.so:-install_name ${EROOT%/}/usr/$(get_libdir)/libRmath.dylib:" \
				src/nmath/standalone/Makefile.in || die
		else
			append-ldflags -Wl,-rpath="${EROOT%/}/usr/$(get_libdir)/R/lib"
		fi
	fi
	AT_M4DIR=m4 eaclocal
	eautoconf
}

src_configure() {
#  Fine tuning of the installation directories:
#    --bindir=DIR            user executables [EPREFIX/bin]
#    --sbindir=DIR           system admin executables [EPREFIX/sbin]
#    --libexecdir=DIR        program executables [EPREFIX/libexec]
#    --sysconfdir=DIR        read-only single-machine data [PREFIX/etc]
#    --sharedstatedir=DIR    modifiable architecture-independent data [PREFIX/com]
#    --localstatedir=DIR     modifiable single-machine data [PREFIX/var]
#    --libdir=DIR            object code libraries [EPREFIX/lib]
#    --includedir=DIR        C header files [PREFIX/include]
#    --oldincludedir=DIR     C header files for non-gcc [/usr/include]
#    --datarootdir=DIR       read-only arch.-independent data root [PREFIX/share]
#    --datadir=DIR           read-only architecture-independent data [DATAROOTDIR]
#    --infodir=DIR           info documentation [DATAROOTDIR/info]
#    --localedir=DIR         locale-dependent data [DATAROOTDIR/locale]
#    --mandir=DIR            man documentation [DATAROOTDIR/man]
#    --docdir=DIR            documentation root [DATAROOTDIR/doc/R]
#    --htmldir=DIR           html documentation [DOCDIR]
#    --dvidir=DIR            dvi documentation [DOCDIR]
#    --pdfdir=DIR            pdf documentation [DOCDIR]
#    --psdir=DIR             ps documentation [DOCDIR]
	econf \
		--bindir="${EPREFIX}"/usr/local/${PN}-${R_VERSION_MINOR}/bin \
		--includedir="${EPREFIX}"/usr/local/${PN}-${R_VERSION_MINOR}/include \
        --datarootdir="${EPREFIX}"/usr/share \
        --docdir="${EPREFIX}"/usr/share/doc/${PN}-${R_VERSION_MINOR} \
        --libdir="${EPREFIX}"/usr/local/${PN}-${R_VERSION_MINOR} \
		--mandir="${EPREFIX}"/usr/local/${PN}-${R_VERSION_MINOR}/man \
		--infodir="${EPREFIX}"/usr/local/${PN}-${R_VERSION_MINOR}/info \
		--htmldir="${EPREFIX}"/usr/local/${PN}-${R_VERSION_MINOR}/html \
		--enable-byte-compiled-packages \
		--enable-R-shlib \
		--disable-R-framework \
		$(use_with zlib system-zlib) \
		$(use_with bzip2 system-bzlib) \
		$(use_with pcre system-pcre) \
		$(use_with lzma system-xz) \
		$(use_enable nls) \
		$(use_enable openmp) \
		$(use_enable profile R-profiling) \
		$(use_enable profile memory-profiling) \
		$(use_enable static-libs static) \
		$(use_enable static-libs R-static-lib) \
		$(use_with cairo) \
		$(use_with icu ICU) \
		$(use_with jpeg jpeglib) \
		$(use_with lapack) \
		$(use_with blas blas "$($(tc-getPKG_CONFIG) --libs blas)") \
		$(use_with !minimal recommended-packages) \
		$(use_with png libpng) \
		$(use_with readline) \
		$(use_with tiff libtiff) \
		$(use_with tk tcltk) \
		$(use_with tk tk-config "${EPREFIX}"/usr/lib/tkConfig.sh) \
		$(use_with tk tcl-config "${EPREFIX}"/usr/lib/tclConfig.sh) \
		$(use_with X x)\
		$(use_enable static-libs static)
		$(use_enable shared-libs shared)
}

src_compile() {
	export VARTEXFONTS="${T}/fonts"
	emake AR="$(tc-getAR)"
	emake -C src/nmath/standalone \
		shared $(use static-libs && echo static) AR="$(tc-getAR)"
	use doc && emake info pdf
}

src_install() {
	default
	emake -j1 -C src/nmath/standalone DESTDIR="${D}" install

	if use doc; then
		emake DESTDIR="${D}" install-info install-pdf
		dosym ../manual /usr/share/doc/${PF}/html/manual
	fi

	# this should be part of eselect R.
	# cat > 99R <<-EOF
	# 	LDPATH=${R_DIR}/lib
	# 	R_HOME=${R_DIR}
	# EOF
	# doenvd 99R
	use bash-completion && newbashcomp "${WORKDIR}"/${BCP} ${PN}-${R_VERSION_MINOR}
	# The buildsystem has a different understanding of install_names than
	# we require.  Since it builds modules like shared objects (wrong), many
	# objects (all modules) get an incorrect install_name.  Fixing the build
	# system here is not really trivial.
	if [[ ${CHOST} == *-darwin* ]] ; then
		local mod
		pushd "${ED}"/usr/lib/R > /dev/null
		for mod in $(find . -name "*.dylib") ; do
			mod=${mod#./}
			install_name_tool -id "${EPREFIX}/usr/lib/R/${mod}" \
				"${mod}"
		done
		popd > /dev/null
	fi
	docompress -x /usr/share/doc/${PF}/NEWS.rds
	dosym "${EPREFIX}"/usr/local/${PN}-${R_VERSION_MINOR}/bin/R "${EPREFIX}"/usr/bin/R-${R_VERSION_MINOR}
	dosym "${EPREFIX}"/usr/local/${PN}-${R_VERSION_MINOR}/bin/Rscript "${EPREFIX}"/usr/bin/Rscript-${R_VERSION_MINOR}
}

pkg_postinst() {
	if [[ ! -n $(readlink "${ROOT}"usr/bin/ruby) ]] ; then
		eselect R set R-${R_VERSION_MINOR}
	fi
	if use java; then
		einfo "Re-initializing java paths for ${P}"
		/usr/bin/R-${PV} CMD javareconf
	fi
}
