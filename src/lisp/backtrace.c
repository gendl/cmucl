/* 
 * Simple backtrace facility.  More or less from Rob's lisp version.
 */

#include <stdio.h>
#include <signal.h>
#include "lisp.h"
#include "internals.h"
#include "globals.h"
#include "os.h"
#include "interrupt.h"
#include "lispregs.h"

#if !(defined(i386) || defined(__x86_64))

/* Sigh ... I know what the call frame looks like and it had
   better not change. */

struct call_frame {
#ifndef alpha
    struct call_frame *old_cont;
#else
    u32 old_cont;
#endif
    lispobj saved_lra;
    lispobj code;
    lispobj other_state[5];
};

struct call_info {
#ifndef alpha
    struct call_frame *frame;
#else
    u32 frame;
#endif
    int interrupted;
#ifndef alpha
    struct code *code;
#else
    u32 code;
#endif
    lispobj lra;
    int pc;			/* Note: this is the trace file offset, not the actual pc. */
};

#define HEADER_LENGTH(header) ((header)>>8)

static int previous_info(struct call_info *info);

static struct code *
code_pointer(lispobj object)
{
    lispobj *headerp, header;
    int type, len;

    headerp = (lispobj *) PTR(object);
    header = *headerp;
    type = TypeOf(header);

    switch (type) {
      case type_CodeHeader:
	  break;
      case type_ReturnPcHeader:
      case type_FunctionHeader:
      case type_ClosureFunctionHeader:
	  len = HEADER_LENGTH(header);
	  if (len == 0)
	      headerp = NULL;
	  else
	      headerp -= len;
	  break;
      default:
	  headerp = NULL;
    }

    return (struct code *) headerp;
}

static boolean
cs_valid_pointer_p(struct call_frame *pointer)
{
    return (((char *) control_stack <= (char *) pointer) &&
	    ((char *) pointer < (char *) current_control_stack_pointer));
}

static void
info_from_lisp_state(struct call_info *info)
{
    info->frame = (struct call_frame *) current_control_frame_pointer;
    info->interrupted = 0;
    info->code = NULL;
    info->lra = 0;
    info->pc = 0;

    previous_info(info);
}

static void
info_from_sigcontext(struct call_info *info, os_context_t * csp)
{
    unsigned long pc;

    info->interrupted = 1;
    if (LowtagOf(SC_REG(csp, reg_CODE)) == type_FunctionPointer) {
	/* We tried to call a function, but crapped out before $CODE could be fixed up.  Probably an undefined function. */
	info->frame = (struct call_frame *) SC_REG(csp, reg_OCFP);
	info->lra = (lispobj) SC_REG(csp, reg_LRA);
	info->code = code_pointer(info->lra);
	pc = (unsigned long) PTR(info->lra);
    } else {
	info->frame = (struct call_frame *) SC_REG(csp, reg_CFP);
	info->code = code_pointer(SC_REG(csp, reg_CODE));
	info->lra = NIL;
	pc = SC_PC(csp);
    }
    if (info->code != NULL)
	info->pc = pc - (unsigned long) info->code -
#ifndef alpha
	    (HEADER_LENGTH(info->code->header) * sizeof(lispobj));
#else
	    (HEADER_LENGTH(((struct code *) info->code)->header) * sizeof(lispobj));
#endif
    else
	info->pc = 0;
}

static int
previous_info(struct call_info *info)
{
    struct call_frame *this_frame;
    int free;
    os_context_t *csp;

    if (!cs_valid_pointer_p(info->frame)) {
	printf("Bogus callee value (0x%08lx).\n", (unsigned long) info->frame);
	return 0;
    }

    this_frame = info->frame;
    info->lra = this_frame->saved_lra;
    info->frame = this_frame->old_cont;
    info->interrupted = 0;

    if (info->frame == NULL || info->frame == this_frame)
	return 0;

    if (info->lra == NIL) {
	/* We were interrupted.  Find the correct sigcontext. */
	free = SymbolValue(FREE_INTERRUPT_CONTEXT_INDEX) >> 2;
	while (free-- > 0) {
	    csp = lisp_interrupt_contexts[free];
	    if ((struct call_frame *) (SC_REG(csp, reg_CFP)) == info->frame) {
		info_from_sigcontext(info, csp);
		break;
	    }
	}
    } else {
	info->code = code_pointer(info->lra);
	if (info->code != NULL)
	    info->pc = (unsigned long) PTR(info->lra) -
		(unsigned long) info->code -
#ifndef alpha
		(HEADER_LENGTH(info->code->header) * sizeof(lispobj));
#else
		(HEADER_LENGTH(((struct code *) info->code)->header) * sizeof(lispobj));
#endif
	else
	    info->pc = 0;
    }

    return 1;
}

void
backtrace(int nframes)
{
    struct call_info info;

    info_from_lisp_state(&info);

    do {
	printf("<Frame 0x%08lx%s, ", (unsigned long) info.frame,
	       info.interrupted ? " [interrupted]" : "");

	if (info.code != (struct code *) 0) {
	    lispobj function;

	    printf("CODE: 0x%08lX, ",
		   (unsigned long) info.code | type_OtherPointer);

#ifndef alpha
	    function = info.code->entry_points;
#else
	    function = ((struct code *) info.code)->entry_points;
#endif
	    while (function != NIL) {
		struct function *header;
		lispobj name;

		header = (struct function *) PTR(function);
		name = header->name;

		if (LowtagOf(name) == type_OtherPointer) {
		    lispobj *object;

		    object = (lispobj *) PTR(name);

		    if (TypeOf(*object) == type_SymbolHeader) {
			struct symbol *symbol;

			symbol = (struct symbol *) object;
			object = (lispobj *) PTR(symbol->name);
		    }
		    if (TypeOf(*object) == type_SimpleString) {
			struct vector *string;
                        char c_string[1000];
			string = (struct vector *) object;
                        convert_lisp_string(c_string, string->data, string->length >> 2);
			printf("%s, ", c_string);
		    } else
			printf("(Not simple string??\?), ");
		} else
		    printf("(Not other pointer??\?), ");


		function = header->next;
	    }
	} else
	    printf("CODE: ???, ");

	if (info.lra != NIL)
	    printf("LRA: 0x%08lx, ", (unsigned long) info.lra);
	else
	    printf("<no LRA>, ");

	if (info.pc)
	    printf("PC: 0x%x>\n", info.pc);
	else
	    printf("PC: ??\?>\n");

    } while (--nframes > 0 && previous_info(&info));
}

#else /* (defined(i386) || defined(__x86_64)) */

#include "x86-validate.h"
#include "gc.h"

#define VM_OCFP_SAVE_OFFSET		0
#define VM_RETURN_PC_SAVE_OFFSET	1

static int
stack_pointer_p(unsigned long p)
{
    return ((void *)p < (void *)control_stack + control_stack_size
	    && p > (unsigned long) &p && (p & 3) == 0);
}

static int
ra_pointer_p(unsigned long ra)
{
    return ra > 4096 && !stack_pointer_p(ra);
}

static unsigned long
deref(unsigned long p, int offset)
{
    return *((unsigned long *) p + offset);
}

static void
print_entry_name(lispobj name)
{
    if (LowtagOf(name) == type_ListPointer) {
	putchar('(');
	while (name != NIL) {
	    struct cons *cons = (struct cons *) PTR(name);

	    print_entry_name(cons->car);
	    name = cons->cdr;
	    if (name != NIL)
		putchar(' ');
	}
	putchar(')');
    } else if (LowtagOf(name) == type_OtherPointer) {
	lispobj *object = (lispobj *) PTR(name);

	if (TypeOf(*object) == type_SymbolHeader) {
	    struct symbol *symbol = (struct symbol *) object;
	    struct vector *string;
	    char c_string[1000];

	    if (symbol->package != NIL) {
		struct instance *pkg = (struct instance *) PTR(symbol->package);
		lispobj pkg_name = pkg->slots[2];

		string = (struct vector *) PTR(pkg_name);
		convert_lisp_string(c_string, string->data, string->length >> 2);
		printf("%s:;", c_string);
	    }

	    object = (lispobj *) PTR(symbol->name);
	    string = (struct vector *) object;
	    convert_lisp_string(c_string, string->data, string->length >> 2);
	    printf("%s:;", c_string);
	} else if (TypeOf(*object) == type_SimpleString) {
	    struct vector *string = (struct vector *) object;
	    char c_string[1000];
	    convert_lisp_string(c_string, string->data, string->length >> 2);
	    printf("\"%s\"", c_string);
	} else
	    printf("<??? type %d>", (int) TypeOf(*object));
    } else
	printf("<??? lowtag %d>", (int) LowtagOf(name));
}

static void
print_entry_points(struct code *code)
{
    lispobj function = code->entry_points;

    while (function != NIL) {
	struct function *header = (struct function *) PTR(function);

	print_entry_name(header->name);

	function = header->next;
	if (function != NIL)
	    printf(", ");
    }
}

/* See also X86-CALL-CONTEXT in code:debug-int.  */

static int
x86_call_context(unsigned long fp, unsigned long *ra, unsigned long *ocfp)
{
    unsigned long lisp_ocfp, lisp_ra, c_ocfp, c_ra;
    int lisp_valid_p, c_valid_p;

    if (!stack_pointer_p(fp))
	return 0;

    lisp_ocfp = deref(fp, -(1 + VM_OCFP_SAVE_OFFSET));
    lisp_ra = deref(fp, -(1 + VM_RETURN_PC_SAVE_OFFSET));
    c_ocfp = deref(fp, 0);
    c_ra = deref(fp, 1);

    lisp_valid_p = (lisp_ocfp > fp && stack_pointer_p(lisp_ocfp)
		    && ra_pointer_p(lisp_ra));
    c_valid_p = (c_ocfp > fp && stack_pointer_p(c_ocfp)
		 && ra_pointer_p(c_ra));

    if (lisp_valid_p && c_valid_p) {
	unsigned long lisp_path_fp, c_path_fp, dummy;
	int lisp_path_p = x86_call_context(lisp_ocfp, &lisp_path_fp, &dummy);
	int c_path_p = x86_call_context(c_ocfp, &c_path_fp, &dummy);

	if (lisp_path_p && c_path_p) {
#if defined __FreeBSD__ && __FreeBSD_version > 400000
	    if (lisp_ocfp > c_ocfp)
		*ra = lisp_ra, *ocfp = lisp_ocfp;
	    else
		*ra = c_ra, *ocfp = c_ocfp;
#else
	    *ra = lisp_ra, *ocfp = lisp_ocfp;
#endif
	} else if (lisp_path_p)
	    *ra = lisp_ra, *ocfp = lisp_ocfp;
	else if (c_path_p)
	    *ra = c_ra, *ocfp = c_ocfp;
	else
	    return 0;
    } else if (lisp_valid_p)
	*ra = lisp_ra, *ocfp = lisp_ocfp;
    else if (c_valid_p)
	*ra = c_ra, *ocfp = c_ocfp;
    else
	return 0;

    return 1;
}

struct compiled_debug_info {
    lispobj header;
    lispobj layout;
    lispobj name;
    lispobj source;
    lispobj package;
    lispobj function_map;
};

struct compiled_debug_function {
    lispobj header;
    lispobj layout;
    lispobj name;
    lispobj kind;
    lispobj variables;
    lispobj blocks;
    lispobj tlf_number;
    lispobj arguments;
    lispobj returns;
    lispobj return_pc;
    lispobj old_fp;
    lispobj nfp;
    lispobj start_pc;
    lispobj elsewhere_pc;
};

static int
array_of_type_p(lispobj obj, int type)
{
    return (LowtagOf(obj) == type_OtherPointer
	    && TypeOf(*(lispobj *) PTR(obj)) == type);
}

struct compiled_debug_function *
debug_function_from_pc(struct code *code, unsigned long pc)
{
    unsigned long code_header_len = sizeof(lispobj) * HeaderValue(code->header);
    unsigned long offset = pc - (unsigned long) code - code_header_len;

    if (LowtagOf(code->debug_info) == type_InstancePointer) {
	struct compiled_debug_info *di

	    = (struct compiled_debug_info *) PTR(code->debug_info);

	if (array_of_type_p(di->function_map, type_SimpleVector)) {
	    struct vector *v = (struct vector *) PTR(di->function_map);
	    long i, len = fixnum_value(v->length);
	    struct compiled_debug_function *df
		= (struct compiled_debug_function *) PTR(v->data[0]);

	    if (len == 1)
		return df;
	    else {
		int elsewhere_p = offset >= fixnum_value(df->elsewhere_pc);

		for (i = 1;; i += 2) {
		    unsigned long next_pc;

		    if (i == len)
			return ((struct compiled_debug_function *)
				PTR(v->data[i - 1]));

		    if (elsewhere_p) {
			struct compiled_debug_function *p
			    = ((struct compiled_debug_function *)
			       PTR(v->data[i + 1]));

			next_pc = fixnum_value(p->elsewhere_pc);
		    } else
			next_pc = fixnum_value(v->data[i]);

		    if (offset < next_pc)
			return ((struct compiled_debug_function *)
				PTR(v->data[i - 1]));
		}
	    }
	}
	    else if (array_of_type_p(di->function_map,
				     type_SimpleArrayUnsignedByte8)) {
	    /* Minimal debug info as described in debug-int.lisp.
	       Not implemented.  */
	}
    }

    return NULL;
}

void
backtrace(int nframes)
{
    unsigned long fp;
    int i;

    __asm__("movl %%ebp,%0":"=g"(fp));

    for (i = 0; i < nframes; ++i) {
	lispobj *p;
	unsigned long ra, next_fp;

	if (!x86_call_context(fp, &ra, &next_fp))
	    break;

	printf("%4d: ", i);

	p = (lispobj *) component_ptr_from_pc((lispobj *) ra);
	if (p && TypeOf(*p) == type_CodeHeader) {
	    struct code *cp = (struct code *) p;
	    struct compiled_debug_function *df;

	    df = debug_function_from_pc(cp, ra);
	    if (df)
		print_entry_name(df->name);
	    else
		print_entry_points(cp);
	} else if (p)
	    printf("<Not implemented, type = %d>", (int) TypeOf(*p));
	else
	    printf("Foreign fp = 0x%lx, ra = 0x%lx", next_fp, ra);

	putchar('\n');
	fp = next_fp;
    }
}

#endif /* (defined(i386) || defined(__x86_64)) */
