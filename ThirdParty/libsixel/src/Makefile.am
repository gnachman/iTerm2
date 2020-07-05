
srcdir = @srcdir@
top_srcdir = @top_srcdir@
VPATH = @srcdir@
prefix = @prefix@
exec_prefix = @exec_prefix@
top_builddir = @top_builddir@
builddir = @builddir@

if COND_GCOV
MAYBE_COVERAGE = --coverage
endif

CLEANFILES = *.gcno *.gcda *.gcov *.log test-output.* tests

lib_LTLIBRARIES = libsixel.la
libsixel_la_SOURCES = \
		$(srcdir)/output.c \
		$(srcdir)/output.h \
		$(srcdir)/fromsixel.c \
		$(srcdir)/tosixel.c \
		$(srcdir)/quant.c \
		$(srcdir)/quant.h \
		$(srcdir)/dither.c \
		$(srcdir)/dither.h \
		$(srcdir)/frame.c \
		$(srcdir)/frame.h \
		$(srcdir)/pixelformat.c \
		$(srcdir)/pixelformat.h \
		$(srcdir)/scale.c \
		$(srcdir)/chunk.c \
		$(srcdir)/chunk.h \
		$(srcdir)/loader.c \
		$(srcdir)/loader.h \
		$(srcdir)/frompnm.c \
		$(srcdir)/frompnm.h \
		$(srcdir)/fromgif.c \
		$(srcdir)/fromgif.h \
		$(srcdir)/encoder.c \
		$(srcdir)/encoder.h \
		$(srcdir)/decoder.c \
		$(srcdir)/decoder.h \
		$(srcdir)/stb_image.h \
		$(srcdir)/writer.c \
		$(srcdir)/writer.h \
		$(srcdir)/stb_image_write.c \
		$(srcdir)/stb_image_write.h \
		$(srcdir)/status.c \
		$(srcdir)/status.h \
		$(srcdir)/malloc_stub.c \
		$(srcdir)/malloc_stub.h \
		$(srcdir)/allocator.c \
		$(srcdir)/allocator.h \
		$(srcdir)/tty.c \
		$(srcdir)/tty.h \
		$(srcdir)/rgblookup.h
libsixel_la_CPPFLAGS = -I$(top_builddir)/include/
libsixel_la_CFLAGS = $(CFLAGS) $(AM_CFLAGS) $(MAYBE_COVERAGE) \
		$(LIBCURL_CFLAGS) \
		$(LIBPNG_CFLAGS) \
		$(LIBJPEG_CFLAGS) \
		$(GDK_PIXBUF_CFLAGS) \
		$(GD_CFLAGS)
libsixel_la_LDFLAGS = -no-undefined -version-info $(LS_LTVERSION)
libsixel_la_LIBADD = -lm \
		$(LIBCURL_LIBS) \
		$(LIBPNG_LIBS) \
		$(LIBJPEG_LIBS) \
		$(GDK_PIXBUF_LIBS) \
		$(GD_LIBS)

if COND_TESTS
noinst_PROGRAMS = tests
tests_SOURCES = $(srcdir)/tests.c
tests_CPPFLAGS = -I$(top_builddir)/include/ \
		 -I$(top_builddir)/src/ $(AM_CPPFLAGS)
tests_CFLAGS = $(CFLAGS) $(AM_CFLAGS) $(MAYBE_COVERAGE)
tests_LDADD = $(srcdir)/libsixel.la
endif

dist_man_MANS = $(srcdir)/sixel.5
EXTRA_DIST = $(srcdir)/rgblookup.gperf

unittest: all
if COND_TESTS
	$(srcdir)/tests
endif

gen-rgblookup: $(srcdir)/rgblookup.gperf
	gperf -C -N lookup_rgb --ignore-case $< |\
	sed 's/{""}/\{"", 0, 0, 0\}/g'          |\
	astyle                                  > $(srcdir)/rgblookup.h


