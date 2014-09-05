/*

 This code was written as part of the CMU Common Lisp project at
 Carnegie Mellon University, and has been placed in the public domain.

*/

#include <stdio.h>
#include <stdlib.h>

#include "lisp.h"
#include "globals.h"
#include "validate.h"
#include "os.h"
#include "internals.h"
#include "arch.h"
#include "lispregs.h"
#include "signal.h"
#include "alloc.h"
#include "interrupt.h"
#include "interr.h"
#include "breakpoint.h"

#define BREAKPOINT_INST 0xcc	/* INT3 */

unsigned long fast_random_state = 1;

#if defined(SOLARIS)
/*
 * Use the /dev/cpu/self/cpuid interface on Solaris.  We could use the
 * same method below, but the Sun C compiler miscompiles the inline
 * assembly.
 */

#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>

void cpuid(int level, unsigned int* a, unsigned int* b,
           unsigned int* c, unsigned int* d)
{
    int device;
    uint32_t regs[4];
    static const char devname[] = "/dev/cpu/self/cpuid";

        *a = *b = *c = *d = 0;
    if ((device = open(devname, O_RDONLY)) == -1) {
        perror(devname);
        goto exit;
    }

    if (pread(device, regs, sizeof(regs), 1) != sizeof(regs)) {
        perror(devname);
        goto exit;
    }

    *a = regs[0];
    *b = regs[1];
    *c = regs[2];
    *d = regs[3];

  exit:
    (void) close(device);

    return;
}

#else
#define __cpuid(level, a, b, c, d)			\
  __asm__ ("xchgl\t%%ebx, %1\n\t"			\
	   "cpuid\n\t"					\
	   "xchgl\t%%ebx, %1\n\t"			\
	   : "=a" (a), "=r" (b), "=c" (c), "=d" (d)	\
	   : "0" (level))

void cpuid(int level, unsigned int* a, unsigned int* b,
           unsigned int* c, unsigned int* d)
{
    unsigned int eax, ebx, ecx, edx;
    
    __cpuid(level, eax, ebx, ecx, edx);

    *a = eax;
    *b = ebx;
    *c = ecx;
    *d = edx;
}
#endif

int
arch_support_sse2(void)
{
    unsigned int eax, ebx, ecx, edx;

    cpuid(1, &eax, &ebx, &ecx, &edx);

    /* Return non-zero if SSE2 is supported */
    return edx & 0x4000000;
}

char *
arch_init(fpu_mode_t mode)
{
    int have_sse2;

    have_sse2 = arch_support_sse2() && os_support_sse2();
    
    if (!have_sse2) {
        fprintf(stderr, "CMUCL requires a SSE2 support; exiting\n");
        abort();
    }
        
    switch (mode) {
      case AUTO:
      case X87:
          fprintf(stderr, "fpu mode AUTO or X87 is not longer supported.\n");
          /* Fall through and return the sse2 core */
      case SSE2:
          return "lisp-sse2.core";
          break;
      default:
          abort();
    }
}



/*
 * Assuming we get here via an INT3 xxx instruction, the PC now
 * points to the interrupt code (lisp value) so we just move past
 * it. Skip the code, then if the code is an error-trap or
 * Cerror-trap then skip the data bytes that follow.
 */

void
arch_skip_instruction(os_context_t * context)
{
    int vlen, code;

    DPRINTF(0, (stderr, "[arch_skip_inst at %lx>]\n", SC_PC(context)));

    /* Get and skip the lisp error code. */
    code = *(char *) SC_PC(context)++;
    switch (code) {
      case trap_Error:
      case trap_Cerror:
	  /* Lisp error arg vector length */
	  vlen = *(char *) SC_PC(context)++;
	  /* Skip lisp error arg data bytes */
	  while (vlen-- > 0)
	      SC_PC(context)++;
	  break;

      case trap_Breakpoint:
      case trap_FunctionEndBreakpoint:
	  break;

      case trap_PendingInterrupt:
      case trap_Halt:
	  /* Only needed to skip the Code. */
	  break;

      default:
	  fprintf(stderr, "[arch_skip_inst invalid code %d\n]\n", code);
	  break;
    }

    DPRINTF(0, (stderr, "[arch_skip_inst resuming at %lx>]\n", SC_PC(context)));
}

unsigned char *
arch_internal_error_arguments(os_context_t * context)
{
    return (unsigned char *) (SC_PC(context) + 1);
}

boolean
arch_pseudo_atomic_atomic(os_context_t * context)
{
    return SymbolValue(PSEUDO_ATOMIC_ATOMIC);
}

void
arch_set_pseudo_atomic_interrupted(os_context_t * context)
{
    SetSymbolValue(PSEUDO_ATOMIC_INTERRUPTED, make_fixnum(1));
}



unsigned long
arch_install_breakpoint(void *pc)
{
    unsigned long result = *(unsigned long *) pc;

    *(char *) pc = BREAKPOINT_INST;	/* x86 INT3       */
    *((char *) pc + 1) = trap_Breakpoint;	/* Lisp trap code */

    return result;
}

void
arch_remove_breakpoint(void *pc, unsigned long orig_inst)
{
    *((char *) pc) = orig_inst & 0xff;
    *((char *) pc + 1) = (orig_inst & 0xff00) >> 8;
}



/*
 * When single stepping single_stepping holds the original instruction
 * pc location.
 */

unsigned int *single_stepping = NULL;

#ifndef __linux__
unsigned int single_step_save1;
unsigned int single_step_save2;
unsigned int single_step_save3;
#endif

void
arch_do_displaced_inst(os_context_t * context, unsigned long orig_inst)
{
    unsigned int *pc = (unsigned int *) SC_PC(context);

    /*
     * Put the original instruction back.
     */

    *((char *) pc) = orig_inst & 0xff;
    *((char *) pc + 1) = (orig_inst & 0xff00) >> 8;

#ifdef SC_EFLAGS
    /* Enable single-stepping */
    SC_EFLAGS(context) |= 0x100;
#else

    /*
     * Install helper instructions for the single step:
     *    nop; nop; nop; pushf; or [esp],0x100; popf.
     *
     * The or instruction enables the trap flag which enables
     * single-stepping.  So when the popf instruction is run, we start
     * single-stepping and stop on the next instruction.
     */

    DPRINTF(0, (stderr, "Installing helper instructions\n"));
    
    single_step_save1 = *(pc - 3);
    single_step_save2 = *(pc - 2);
    single_step_save3 = *(pc - 1);
    *(pc - 3) = 0x9c909090;
    *(pc - 2) = 0x00240c81;
    *(pc - 1) = 0x9d000001;
#endif

    single_stepping = (unsigned int *) pc;

#ifndef SC_EFLAGS
    /*
     * pc - 9 points to the pushf instruction that we installed for
     * the helper.
     */
    
    DPRINTF(0, (stderr, " Setting pc to pushf instruction at %p\n", (void*) ((char*) pc - 9)));
    SC_PC(context) = (int)((char *) pc - 9);
#endif
}


void
sigtrap_handler(HANDLER_ARGS)
{
    unsigned int trap;
    os_context_t* os_context = (os_context_t *) context;
#if 0
    fprintf(stderr, "x86sigtrap: %8x %x\n",
            SC_PC(os_os_context), *(unsigned char *) (SC_PC(os_context) - 1));
    fprintf(stderr, "sigtrap(%d %d %x)\n", signal, CODE(code), os_context);
#endif

    if (single_stepping && (signal == SIGTRAP)) {
#if 0
	fprintf(stderr, "* Single step trap %p\n", single_stepping);
#endif

#ifdef SC_EFLAGS
	/* Disable single-stepping */
	SC_EFLAGS(os_context) ^= 0x100;
#else
	/* Un-install single step helper instructions. */
	*(single_stepping - 3) = single_step_save1;
	*(single_stepping - 2) = single_step_save2;
	*(single_stepping - 1) = single_step_save3;
        DPRINTF(0, (stderr, "Uninstalling helper instructions\n"));
#endif

	/*
	 * Re-install the breakpoint if possible.
	 */
	if ((int) SC_PC(os_context) == (int) single_stepping + 1)
	    fprintf(stderr, "* Breakpoint not re-install\n");
	else {
	    char *ptr = (char *) single_stepping;

	    ptr[0] = BREAKPOINT_INST;	/* x86 INT3 */
	    ptr[1] = trap_Breakpoint;
	}

	single_stepping = NULL;
	return;
    }

    /* This is just for info in case monitor wants to print an approx */
    current_control_stack_pointer = (unsigned long *) SC_SP(os_context);

    RESTORE_FPU(os_context);

    /*
     * On entry %eip points just after the INT3 byte and aims at the
     * 'kind' value (eg trap_Cerror). For error-trap and Cerror-trap a
     * number of bytes will follow, the first is the length of the byte
     * arguments to follow.
     */

    trap = *(unsigned char *) SC_PC(os_context);

    switch (trap) {
      case trap_PendingInterrupt:
	  DPRINTF(0, (stderr, "<trap Pending Interrupt.>\n"));
	  arch_skip_instruction(os_context);
	  interrupt_handle_pending(os_context);
	  break;

      case trap_Halt:
	  {
              FPU_STATE(fpu_state);
              save_fpu_state(fpu_state);

	      fake_foreign_function_call(os_context);
	      lose("%%primitive halt called; the party is over.\n");
	      undo_fake_foreign_function_call(os_context);

              restore_fpu_state(fpu_state);
	      arch_skip_instruction(os_context);
	      break;
	  }

      case trap_Error:
      case trap_Cerror:
	  DPRINTF(0, (stderr, "<trap Error %x>\n", CODE(code)));
	  interrupt_internal_error(signal, code, os_context, CODE(code) == trap_Cerror);
	  break;

      case trap_Breakpoint:
#if 0
	  fprintf(stderr, "*C break\n");
#endif
	  SC_PC(os_context) -= 1;

	  handle_breakpoint(signal, CODE(code), os_context);
#if 0
	  fprintf(stderr, "*C break return\n");
#endif
	  break;

      case trap_FunctionEndBreakpoint:
	  SC_PC(os_context) -= 1;
	  SC_PC(os_context) =
	      (int) handle_function_end_breakpoint(signal, CODE(code), os_context);
	  break;

#ifdef trap_DynamicSpaceOverflowWarning
      case trap_DynamicSpaceOverflowWarning:
	  interrupt_handle_space_overflow(SymbolFunction
					  (DYNAMIC_SPACE_OVERFLOW_WARNING_HIT),
					  os_context);
	  break;
#endif
#ifdef trap_DynamicSpaceOverflowError
      case trap_DynamicSpaceOverflowError:
	  interrupt_handle_space_overflow(SymbolFunction
					  (DYNAMIC_SPACE_OVERFLOW_ERROR_HIT),
					  os_context);
	  break;
#endif
      default:
	  DPRINTF(0,
		  (stderr, "[C--trap default %d %d %p]\n", signal, CODE(code),
		   os_context));
	  interrupt_handle_now(signal, code, os_context);
	  break;
    }
}

void
arch_install_interrupt_handlers(void)
{
    interrupt_install_low_level_handler(SIGILL, sigtrap_handler);
    interrupt_install_low_level_handler(SIGTRAP, sigtrap_handler);
}


extern lispobj call_into_lisp(lispobj fun, lispobj * args, int nargs);

/* These next four functions are an interface to the 
 * Lisp call-in facility. Since this is C we can know
 * nothing about the calling environment. The control
 * stack might be the C stack if called from the monitor
 * or the Lisp stack if called as a result of an interrupt
 * or maybe even a separate stack. The args are most likely
 * on that stack but could be in registers depending on
 * what the compiler likes. So I try to package up the
 * args into a portable vector and let the assembly language
 * call-in function figure it out.
 */

lispobj
funcall0(lispobj function)
{
    lispobj *args = NULL;

    return call_into_lisp(function, args, 0);
}

lispobj
funcall1(lispobj function, lispobj arg0)
{
    lispobj args[1];

    args[0] = arg0;
    return call_into_lisp(function, args, 1);
}

lispobj
funcall2(lispobj function, lispobj arg0, lispobj arg1)
{
    lispobj args[2];

    args[0] = arg0;
    args[1] = arg1;
    return call_into_lisp(function, args, 2);
}

lispobj
funcall3(lispobj function, lispobj arg0, lispobj arg1, lispobj arg2)
{
    lispobj args[3];

    args[0] = arg0;
    args[1] = arg1;
    args[2] = arg2;
    return call_into_lisp(function, args, 3);
}

#ifdef LINKAGE_TABLE

#ifndef LinkageEntrySize
#define LinkageEntrySize 8
#endif

void
arch_make_linkage_entry(long linkage_entry, void *target_addr, long type)
{
    char *reloc_addr = (char *) (FOREIGN_LINKAGE_SPACE_START

				 + linkage_entry * LinkageEntrySize);

    if (type == 1) {		/* code reference */
	/* Make JMP to function entry. */
	/* JMP offset is calculated from next instruction. */
	long offset = (char *) target_addr - (reloc_addr + 5);
	int i;

	*reloc_addr++ = 0xe9;	/* opcode for JMP rel32 */
	for (i = 0; i < 4; i++) {
	    *reloc_addr++ = offset & 0xff;
	    offset >>= 8;
	}
	/* write a nop for good measure. */
	*reloc_addr = 0x90;
    } else if (type == 2) {
	*(unsigned long *) reloc_addr = (unsigned long) target_addr;
    }
}

/* Make a call to the first function in the linkage table, which is
   resolve_linkage_tramp. */
void
arch_make_lazy_linkage(long linkage_entry)
{
    char *reloc_addr = (char *) (FOREIGN_LINKAGE_SPACE_START

				 + linkage_entry * LinkageEntrySize);
    long offset = (char *) (FOREIGN_LINKAGE_SPACE_START) - (reloc_addr + 5);
    int i;

    *reloc_addr++ = 0xe8;	/* opcode for CALL rel32 */
    for (i = 0; i < 4; i++) {
	*reloc_addr++ = offset & 0xff;
	offset >>= 8;
    }
    /* write a nop for good measure. */
    *reloc_addr = 0x90;
}

/* Get linkage entry.  The initial instruction in the linkage
   entry is a CALL; the return address we're passed points to the next
   instruction. */

long
arch_linkage_entry(unsigned long retaddr)
{
    return ((retaddr - 5) - FOREIGN_LINKAGE_SPACE_START) / LinkageEntrySize;
}
#endif /* LINKAGE_TABLE */
