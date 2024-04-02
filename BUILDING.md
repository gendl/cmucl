Building CMU CL
===============

This document is intended to give you a general overview of the build
process (i.e. what needs to be done, in what order, and what is it
generally called).  It will also tell you how to set up a suitable
build environment, how the individual scripts fit into the general
scheme of things, and give you a couple of examples.

General Requirements
--------------------

In order to build CMU CL, you will need:

1. A working CMU CL binary.  There is no way around this requirement!

   This binary can either be for the platform you want to target, in
   that case you can either recompile or cross-compile, or for another
   supported platform, in that case you must cross-compile, obviously.

1. A supported C compiler for the C runtime code.

   Most of the time, this means GNU gcc, though for some ports it
   means the vendor-supplied C compiler.  The compiler must be
   available under the name specified by your ports Config file.

   Note for FreeBSD 10 and above: The build requires gcc (Clang will
   not work) and the lib32 compatiblity package.

1. GNU make

   This has to be available either as gmake or make in your PATH, or
   the MAKE environment variable has to be set to point to the correct
   binary.

1. The CMU CL source code

   Here you can either use one of the release source tarballs, or
   check out the source code directly from the public CMUCL git
   repository.

If you want to build CMU CL's Motif interface/toolkit, you'll need a
working version of the Motif libraries, either true-blue OSF/Motif, or
OpenMotif, or Lesstif.  The code was developed against 1.2 Motif,
though recompilation against 2.x Motif probably works as well.

Setting up a build environment
------------------------------

1. Create a base directory and change to it
```
    mkdir cmucl ; cd cmucl
```
2. Fetch the sources and put them into the base directory
```
    tar xzf /tmp/cmucl-source.tar.gz
```

    or, if you want to use the git sources directly:

```
    git clone https://gitlab.common-lisp.net/cmucl/cmucl.git
```

    Whatever you do, the sources must be in a directory named src
    inside the base directory.  Since the build tools keep all
    generated files in separate target directories, the src directory
    can be read-only (e.g. mounted read-only via NFS, etc.)

    The build tools are all in the bin directory.

That's it, you are now ready to build CMU CL.

A quick guide for simple builds
-------------------------------

We recommend that you read all of this document, but in case you don't
want to do that and in case you know, somehow, that the version of
CMUCL you are building from will build the sources you have, here is a
quick guide.

1. Simple builds

   Use this to build from a version of CMUCL that is very close to the
   sources you are trying to build now:

```
   bin/build.sh -C "" -o "<name-of-old-lisp> <options-to-lisp>"
```

   This will build CMUCL 3 times, each time with the result of the
   previous build.  The last time, the additional libraries like CLX,
   CLM, and Hemlock are built.  The final result will be in the
   directory build-4.

   This script basically runs create-target.sh, build-world.sh,
   load-world.sh three times.  See below for descriptions of these
   scripts.
   
1. Slightly more complicated builds

   For slightly more complicated builds, you may need to use some
   bootstrap files.  See below for more information about these
   bootstrap files.  

   For these, you can use this:

```
   bin/build.sh -C "" -o "<old-lisp>" -B boot1.lisp -B boot2.lisp
```

   The bootstrap files listed with the -B option (as many as needed)
   are loaded in order, so be sure to get them right.

   As in a) above, three builds are done, and the result is in the
   directory build-4.

1. More complicated builds

   If you have more complicated builds, this script probably will not
   work, and definitely does not handle cross-compiles.  In this case,
   you will have to invoke the individual scripts by hand, as
   described below.

How do you know which of the three options above apply?  The easiest
way is to look in src/bootfiles/<version>/* for boot files.  If the
file date of a boot file is later than the version of CMUCL you are
building from, then you need to use b) or c) above.  You may need to
read the bootfiles for additional instructions, if any.  

If there are no bootfiles, then you can use 1. above.

The `build.sh` script supports other options, and `bin/build.sh -?`
will give a quick summary.  Read bin/build.sh for more
information. 

A general outline of the build process
--------------------------------------

Building CMU CL can happen in one of two ways:  Normal recompilation,
and cross-compilation.  We'll first look at normal recompilation:

The recompilation process basically consists of 4 phases/parts:

1. Compiling the lisp files that make up the standard kernel.

   This happens in your current CMU CL process, using your current
   CMU CL's normal file compiler.  This phase currently consists of 3
   sub-phases, namely those controlled by src/tools/worldcom.lisp,
   which compiles all the runtime files, src/tools/comcom.lisp, which
   compiles the compiler (including your chosen backend), and finally
   src/tools/pclcom.lisp, which compiles PCL, CMU CL's CLOS
   implementation.  The whole phase is often called "world-compile",
   or "compiling up a world", based on the name of the first
   sub-phase.

1. Building a new kernel.core file out of the so created files

   This process, which is generally called genesis, and which is
   controlled by src/tools/worldbuild.lisp, uses the newly compiled
   files in order to build a new, basic core file, which is then used
   by the last phase to create a fully functional normal core file.
   It does this by "loading" the compiled files into an in-core
   representation of a new core file, which is then dumped out to
   disk, together with lots of fixups that need to happen once the new
   core is started.

   As part of this process, it also creates the file internals.h,
   which contains information about the general memory layout of the
   new core and its basic types, their type tags, and the location of
   several important constants and other variables, that are needed by
   the C runtime code to work with the given core.

   So going through genesis is needed to create internals.h, which is
   needed to compile the C runtime code (i.e. the "lisp" binary).
   However there is a slight circularity here, since genesis needs as
   one of its inputs the file target:lisp/lisp.nm, which contains the
   (slightly pre-treated) output of running nm on the new lisp
   binary.  Genesis uses this information to fixup the addresses of C
   runtime support functions for calls from Lisp code.

   However the circularity isn't complete, since genesis can work with
   an empty/bogus lisp.nm file.  While the kernel.core it then
   produces is unusable, it will create a usable internals.h file,
   which can be used to recompile the C runtime code, producing a
   usable lisp.nm file, which in turn can be used to restart genesis,
   producing a working kernel.core file.

   Genesis also checks whether the newly produced internals.h file
   differs from a pre-existing internals.h file (this might be caused
   by an empty internals.h file if you are rebuilding for the first
   time, or by changes in the lisp sources that cause differences in
   the memory layout of the kernel.core), and informs you of this, so
   that you can recompile the C runtime code, and restart genesis.

   If it doesn't inform you of this, you can skip directly to the last
   phase d).

1. Recompiling the C runtime code, producing the "lisp" binary file

   This step is only needed if you haven't yet got a suitable lisp
   binary, or if the internals.h file has changed during genesis (of
   which genesis informs you), or when you made changes to the C
   sources that you want to take effect.

   Recompiling the C runtime code is controlled by a GNU Makefile, and
   your target's Config file.  It depends on a correct internals.h
   file as produced by genesis.

   Note that whenever you recompile the runtime code, for whatever
   reason, you must redo phase b).  Note that if you make changes to
   the C sources and recompile because of this, you can do that before
   Phase b), so that you don't have to perform that phase twice.

1. Populating the kernel.core, and dumping a new lisp.core file.

   In this phase, which is controlled by src/tools/worldload.lisp, and
   hence often called world-load, the kernel.core file is started up
   using the (possibly new) lisp binary, the remaining files which
   were compiled in phase a) are loaded into it, and a new lisp.core
   file is dumped out.

We're not quite done yet.  This produces just a basic lisp.core.
To complete the build so that you something similar to what the
releases of CMUCL do, there are a few more steps:

1. Build the utilities like Gray streams, simple streams, CLX, CLM,
   and Hemlock.  Use the bin/build-utils.sh script for this, as
   described below

1. Create tarfiles using the bin/make-dist.sh script, as
   explained below.

With these tarfiles, you can install them anywhere.  The contents of
the tarfiles will be the same as the snapshots and releases of CMUCL.

When cross-compiling, there is additional phase at the beginning, and
some of the phases happen with different hosts/platforms.  The initial
phase is setting up and compiling the cross-compilation backend, using
your current compiler.  The new backend is then loaded, and all
compilation in phase a) happens using this compiler backend.  The
creation of the kernel.core file in phase b) happens as usual, while
phase c) of course happens on the target platform (if that differs
from the host platform), as does the final phase d).  Another major
difference is that you can't compile PCL using the cross-compiler, so
one usually does a normal rebuild using the cross-compiled core on the
target platform to get a full CMU CL core.

So, now you know all about CMU CL compilation, how does that map onto
the scripts included with this little text?

Overview of the included build scripts
--------------------------------------

* bin/build.sh [-123obvuBCU?]

    This is the main build script.  It essentially calls the other build
    scripts described below in the proper sequence to build cmucl from an
    existing binary of cmucl.

* bin/create-target.sh target-directory [lisp-variant [motif-variant]]

    This script creates a new target directory, which is a shadow of the
    source directory, that will contain all the files that are created by
    the build process.  Thus, each target's files are completely separate
    from the src directory, which could, in fact, be read-only.  Hence you
    can simultaneously build CMUCL for different targets from the same
    source directory.

    The first argument is the name of the target directory to create.  The
    remaining arguments are optional.  If they are not given, the script
    tries to determine the lisp variant and motif variant from the system
    the script is running on.

    The lisp-variant (i.e. the suffix of the src/lisp/Config.* to use as
    the target's Config file), and optionally the motif-variant (again the
    suffix of the src/motif/server/Config.* file to use as the Config file
    for the target's CMUCL/Motif server code).  If the lisp-variant is
    given but the motif-variant is not, the motif-variant is determined
    from the lisp-variant.

    The script will generate the target directory tree, link the relevant
    Config files, and generate place-holder files for various files, in
    order to ensure proper operation of the other build-scripts.  It also
    creates a sample setenv.lisp file in the target directory, which is
    used by the build and load processes to set up the correct list of
    *features* for your target lisp core.

    IMPORTANT: You will normally NOT have to modify the sample setenv.lisp
    file, if you are building from a binary that has the desired features.
    In fact, the sample has all code commented out, If you want to add or
    remove features, you need to include code that puts at least a minimal
    set of features onto the list (use PUSHNEW and/or REMOVE).  You can
    use the current set of *features* of your lisp as a first guide.  The
    sample setenv.lisp includes a set of features that should work for the
    intended configuration.  Note also that some adding or removing some
    features may require a cross-compile instead of a normal compile.

* bin/clean-target.sh [-l] target-directory [more dirs]

    Cleans the given target directory, so that all created files will be
    removed.  This is useful to force recompilation.  If the -l flag is
    given, then the C runtime is also removed, including all the lisp
    executable, any lisp cores, all object files, lisp.nm, internals.h,
    and the config file.

* bin/build-world.sh target-directory [build-binary] [build-flags...]

    Starts a complete world build for the given target, using the lisp
    binary/core specified as a build host.  The recompilation step will
    only recompile changed files, or files for which the fasl files are
    missing.  It will also not recompile the C runtime code (the lisp
    binary).  If a (re)compilation of that code is needed, the genesis
    step of the world build will inform you of that fact.  In that case,
    you'll have to use the rebuild-lisp.sh script, and then restart the
    world build process with build-world.sh

* bin/rebuild-lisp.sh target-directory

    This script will force a complete recompilation of the C runtime code
    of CMU CL (aka the lisp executable).  Doing this will necessitate
    building a new kernel.core file, using build-world.sh.

* bin/load-world.sh target-directory version

    This will finish the CMU CL rebuilding process, by loading the
    remaining compiled files generated in the world build process into the
    kernel.core file, that also resulted from that process, creating the
    final lisp.core file.

    You have to pass the version string as a second argument.  The dumped
    core will anounce itself using that string.  Please don't use a string
    consisting of an official release name only, (e.g. "18d"), since those
    are reserved for official release builds.  Including the build-date in
    ISO8601 format is often a good idea, e.g. "18d+ 2002-05-06" for a
    binary that is based on sources current on the 6th May, 2002, which is
    post the 18d release.

* bin/build-utils.sh target-directory

    This script will build auxiliary libraries packaged with CMU CL,
    including CLX, CMUCL/Motif, the Motif debugger, inspector, and control
    panel, and the Hemlock editor.  It will use the lisp executable and
    core of the given target.

    Note: To build with Motif (clm), you need to have the Motif libraries
    available and headers available to build motifd, the clm Motif server.
    OpenMotif is known to work.

    You may need to adjust the include paths and library paths in
    src/motif/server/Config.* to match where Motif is installed if the
    paths therein are incorrect.

    Unless you intend to use clm and motifd, you can safely ignore the
    build failure.  Everything else will have been compiled correctly; you
    just can't use clm.

* bin/make-dist.sh [-bg] [-G group] [-O owner] target-directory version arch os

    This script creates both main and extra distribution tarballs from the
    given target directory, using the make-main-dist.sh and
    make-extra-dist.sh scripts.  The result will be two tar files.  One
    contains the main distribution including the runtime and lisp.core
    with PCL (CLOS); the second contains the extra libraries such as
    Gray-streams, simple-streams, CLX, CLM, and Hemlock.

    Some options that are available:

      -b           Use bzip2 compression
      -g           Use gzip compression
      -G group     Group to use
      -O owner     Owner to use

    If you specify both -b and -g, you will get two sets of tarfiles.  The
    -G and -O options will attempt to set the owner and group of the files
    when building the tarfiles.  This way, when you extract the tarfiles,
    the owner and group will be set as specified.  You may need to be root
    to do this because many Unix systems don't normally let you change the
    owner and group of a file.

    The remaining arguments used to create the name of the tarfiles.  The
    names will have the form:

```
   cmucl-<version>-<arch>-<os>.tar.bz2
   cmucl-<version>-<arch>-<os>.extras.tar.bz2
```

    Of course, the "bz2" will be "gz" if you specified gzip compression
    instead of bzip.

* /bin/make-main-dist.sh target-directory version arch os

    This is script is not normally invoked by the user; make-dist will do
    it appropriately.

    This script creates a main distribution tarball (both in gzipped and
    bzipped variants) from the given target directory.  This will include
    all the stuff that is normally included in official release tarballs
    such as lisp.core and the PCL libraries, including Gray streams and
    simple streams.

    This is intended to be run from make-dist.sh.

* bin/make-extra-dist.sh target-directory version arch os

    This is script is not normally invoked by the user; make-dist will do
    it appropriately.

    This script creates an extra distribution tarball (both in gzipped and
    bzipped variants) from the given target directory.  This will include
    all the stuff that is normally included in official extra release
    tarballs, i.e. the auxiliary libraries such as CLX, CLM, and Hemlock.

    This is intended to be run from make-dist.sh.


* cross-build-world.sh target-directory cross-directory cross-script 
                       [build-binary] [build-flags...]

    This is a script that can be used instead of build-world.sh for
    cross-compiling CMUCL.  In addition to the arguments of build-world.sh
    it takes two further required arguments:  The name of a directory that
    will contain the cross-compiler backend (the directory is created if
    it doesn't exist, and must not be the same as the target-directory),
    and the name of a Lisp cross-compilation script, which is responsible
    for setting up, compiling, and loading the cross-compiler backend.
    The latter argument is needed because each host/target combination of
    platform's needs slightly different code to produce a working
    cross-compiler.

    We include a number of working examples of cross-compiler scripts in
    the cross-scripts directory.  You'll have to edit the features section
    of the given scripts, to specify the features that should be removed
    from the current set of features in the host lisp, and those that
    should be added, so that the backend features are correct for the
    intended target.

    You can look at Eric Marsden's collection of build scripts for the
    basis of more cross-compiler scripts.

Step-by-Step Example of recompiling CMUCL for OpenBSD
-----------------------------------------------------

Set up everything as described in the setup section above. Then
execute:
```
# Create a new target directory structure/config for OpenBSD:
bin/create-target.sh openbsd OpenBSD_gencgc OpenBSD

# edit openbsd/setenv.lisp to contain what we want:
cat <<EOF > openbsd/setenv.lisp
;;; Put code to massage *features* list here...

(in-package :user)

(pushnew :openbsd *features*)
(pushnew :bsd *features*)
(pushnew :i486 *features*)
(pushnew :mp *features*)
(pushnew :hash-new *features*)
(pushnew :random-mt19937 *features*)
(pushnew :conservative-float-type *features*)
(pushnew :gencgc *features*)

;;; Version tags

(pushnew :cmu18d *features*)
(pushnew :cmu18 *features*)
(setf *features* (remove :cmu17 *features*))
(setf *features* (remove :cmu18c *features*))
EOF

# Recompile the lisp world, and dump a new kernel.core:
bin/build-world.sh openbsd lisp # Or whatever you need to invoke your 
                              # current lisp binary+core

# If build-world tells you (as it will the first time) that:
# "The C header file has changed. Be sure to re-compile the startup
# code."
# You 'll need to start rebuild-lisp.sh to do that, and then reinvoke
# build-world.sh:

# Recompile lisp binary itself:
bin/rebuild-lisp.sh openbsd

# Restart build-world.sh now:
bin/build-world.sh openbsd lisp

# Now we populate the kernel.core with further compiled files,
# and dump the final lisp.core file:

bin/load-world.sh openbsd "18d+ 2002-05-06"

# The second argument above is the version number that the built
# core will announce.  Please always put the build-date and some
# other information in there, to make it possible to differentiate
# those builds from official builds, which only contain the release.
```

Now you should have a new lisp.core, which you can start with
```
./openbsd/lisp/lisp -core ./openbsd/lisp/lisp.core -noinit -nositeinit
```

Compiling sources that contain disruptive changes
-------------------------------------------------

The above instructions should always work as-is for recompiling CMU CL
using matching binaries and source files.  They also work quite often
when recompiling newer sources.  However, every so often, some change
to the CMU CL sources necessitates some form of bootstrapping, so that
binaries built from earlier sources can compile the sources containing
that change.  There are two forms of boostrapping that can be
required:

1. Bootfiles

   The maintainers try to make bootfiles available, that allow going
   from an old release to the next release.  These are located in the
   src/bootfiles/<old-release>/ directory of the CMU CL sources.

   I.e. if you have binaries that match release 18d, then you'll need
   to use all the bootfiles in src/bootfiles/18d/ in order to go to
   the next release (or current sources, if no release has been made
   yet).  If you already used some of the bootstrap files to compile
   your current lisp, you obviously don't need to use those to get to
   later versions.

   You can use the bootfiles by concatenating them into a file called
   bootstrap.lisp in the target directory (i.e. target:bootstrap.lisp)
   in the order they are numbered.  Be sure to remove the bootstrap
   file once it is no longer needed.

   Alternatively, the bootstrap file can just "load" the individual
   bootfiles as needed.

1. Cross-compiling

   Under some circumstances, bootstrap code will not be sufficient,
   and a cross-compilation is needed.  In that case you will have to
   use cross-build-world.sh, instead of build-world.sh.  Please read
   the instructions of that script for details of the more complex
   procedure.

   << This isn't really true anymore, and we should place a more
      elaborate description of the cross-compiling process here >>

   When cross-compiling, there are two sorts of bootscripts that can be
   used:  Those that want to be executed prior to compiling and loading
   the cross-compiler, which should be placed in the file called
   target:cross-bootstrap.lisp, and those that should happen after the
   cross-compiler has been compiled and loaded, just prior to compiling
   the target, which should be placed in target:bootstrap.lisp, just
   like when doing a normal recompile.

   Additionally, sometimes customized cross-compiler setup scripts
   (to be used in place of e.g. cross-x86-x86.lisp) are required,
   which are also placed in one of the bootfiles/*/* files.  In those
   cases follow the instructions provided in that file, possibly merging
   the changed contents thereof with your normal cross-script.

Step-by-Step Example of Cross-Compiling
---------------------------------------

This gives a step-by-step example of cross-compiling a sparc-v8 build
using a sparc-v9 build.  (For some unknown reason, you can't just
remove the :sparc-v9 feature and add :sparc-v8.)

So, first get a recent sparc-v9 build.  It's best to get a version
that is up-to-date with the sources.  Otherwise, you may also need to
add a bootstrap file to get any bootfiles to make your lisp
up-to-date with the current sources.

1.  Select a directory for the cross-compiler and compiled target:

	Create a cross-compiler directory to hold the cross-compiler
	and a target directory to hold the result:

	       bin/create-target.sh xcross
	       bin/create-target.sh xtarget

2.  Adjust cross-compilation script

	Copy the src/tools/cross-scripts/cross-sparc-sparc.lisp to
	xtarget/cross.lisp.  Edit it appropriately.  In this case, it
	should look something like:

	    (c::new-backend "SPARC"
	       ;; Features to add here
	       '(:sparc :sparc-v8
		 :complex-fp-vops
		 :linkage-table
		 :gencgc
		 :stack-checking
		 :relative-package-names
		 :conservative-float-type
		 :hash-new :random-mt19937
		 :cmu :cmu19 :cmu19a
		 )
	       ;; Features to remove from current *features* here
	       '(:sparc-v9 :sparc-v7 :x86 :x86-bootstrap :alpha :osf1 :mips
		 :propagate-fun-type :propagate-float-type :constrain-float-type
		 :openbsd :freebsd :glibc2 :linux :pentium
		 :long-float :new-random :small))

	    (setf *features* (remove :sparc-v9 *features*))
	    (pushnew :sparc-v8 *features*)

	It's important to add frob *features* here as well as in the
	new-backend.  If you don't adjust *features*, they won't be
	set appropriately in the result.

3.  Build the cross compiler and target
	Now compile the result:

	    bin/cross-build-world.sh xtarget xcross xtarget/cross.lisp [v9 binary]

4.  Rebuild the lisp files:

	When this finishes, you need to compile the C code:

		bin/rebuild-lisp.sh xtarget

	At this point, you may want to run cross-build-world.sh again
	to generate a new kernel.core.  It shouldn't build anything;
	just loads everything and creates a kernel.core.

5.  Build the world:

	With the new kernel.core, we need to create a lisp.core:

		bin/load-world.sh xtarget "new lisp"

	Test the result with

		xtarget/lisp/lisp -noinit

However, this lisp will be missing some functionality like PCL.  You
probably now want to use the compiler to rebuild everything once
again.  Just follow the directions for a normal build, and use
xtarget/lisp/lisp as your compiler.  Be sure to use create-target.sh
to create a new directory where the result can go.

Cross-Platform Cross-Compile
----------------------------

A cross-platform cross-compile is very similar to a normal
cross-compile, and the basic steps are the same.  For the sake of
concreteness, assume we are on ppc/darwin and want to cross-compile
to x86/linux.

To simplify things, we assume that both platforms have access to the
same file system, via NFS or something else.

1. As above, we need to create directories for the cross-compiler and
   compiled target.  We assume we are on ppc/darwin.  So, when running
   create-target.sh we need to specify the target:

        bin/create-target.sh x86-cross x86
        bin/create-target.sh x86-target x86

2. Adjust the cross-compilation script.  An example for ppc/darwin to
   x86/linux is in src/tools/cross-scripts/cross-ppc-x86.lisp.

3. Build the cross compiler and target, as above, using the specified
   cross-compile script:

        bin/cross-build-world.sh x86-target x86-cross cross.lisp [ppc binary]

   where cross.lisp is the cross-compile script from 2) above.

4. Everything has now been compiled for the x86/linux target.  We need
   to compile the C code for x86 and create a lisp.core from the
   kernel.core.  This is where it's useful to have both platforms be
   able to access the same file system.  If not, you will need to copy
   all of the generated files from ppc/darwin to x86/linux.  Basically
   everything in xtarget needs to be copied.

   Note carefully that you may have to edit lisp/internals.h and/or
   lisp/internals.inc to have the correct features.  This is a known
   bug in the generation of these files during cross-compilation.

   Compile the lisp code:

        bin/rebuild-lisp.sh x86-target   

5. Now run load-world.sh to create the desired lisp.core from lisp and
   kernel.core.  As above, PCL has not been compiled, so select
   restart 3 (return nil from pclload) to create lisp.core

        bin/load-world.sh x86-target "new x86"

At this point, you will have a shiny new lisp on the new platform.
Since it's missing PCL, you will need to do at least one normal build
to get PCL included.  This is also a good check to see if everything
was compiled properly.  A full set of builds via build.sh might be
good at this point too.

Some of the details for each command may have changed;  You can get
help for each command by using the -h argument.

In particular steps 3, 4, and 5 can be combined into one by using the
-c, -r, and -l options for cross-build-world.sh.  The -c option cleans
out the targe and cross directories; -r does step 4; and -l does step
5.

