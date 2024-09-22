/*---------------------------------------------------------------------------
  Copyright 2024, Microsoft Research, Daan Leijen, Anton Lorenzen

  This is free software; you can redistribute it and/or modify it under the
  terms of the Apache License, Version 2.0. A copy of the License can be
  found in the LICENSE file at the root of this distribution.
---------------------------------------------------------------------------*/

#include "kklib.h"
#include "kklib/lazy.h"

// Eval lazy value that is unique
// Since the `eval_borrow` is generated and does not give direct access to the argument
// (which is immediately matched against lazy constructors) we cannot recurse on 
// it and we do not have to create a blackhole or indirections (since the result 
// is not shared we can return it as-is).
static kk_datatype_t kk_lazy_eval_unique(kk_block_t* b, kk_function_t eval_borrow, kk_context_t* ctx)
{
  kk_assert(kk_block_is_valid(b));
  kk_assert(kk_block_is_unique(b));
  kk_assert(!kk_block_is_blackhole(b));  // unique lazy value cannot result in a black hole (?)
                                         // (as long as we always use the generated eval_borrow function which does not give access to the value itself?)
  // evaluate
  kk_function_dup(eval_borrow, ctx);
  return kk_datatype_unbox(kk_function_call(kk_box_t, (kk_function_t, kk_box_t, kk_context_t*), eval_borrow, (eval_borrow, kk_block_box(b, ctx), ctx), ctx));
}


// Eval lazy value that is not uniquely referenced but not thread-shared
// 
// Note: we always create an indirection node for now. However, if we can somehow 
// ensure the result of the `eval_borrow` function reuses the argument we could avoid
// allocation in many cases. However, we must prevent reuse of the argument for anything
// else than the result which seems quite difficult to guaratee at compile-time?
static kk_datatype_t kk_lazy_eval_local(kk_block_t* b, kk_function_t eval_borrow, kk_context_t* ctx)
{
  kk_assert(kk_block_is_valid(b));
  kk_assert(!kk_block_is_thread_shared(b));
  kk_assert(!kk_block_is_unique(b));
  kk_assert(kk_block_is_lazy(b));
  if kk_unlikely(kk_block_is_blackhole(b)) {
    // black hole: trying to recursively evaluate the same value
    // we just return it as-is which will result in a pattern match error later on which raises the exception
    return kk_datatype_from_ptr(b,ctx);
  }

  // copy and overwrite the block with a blackhole
  kk_block_t* x = kk_block_alloc_copy(b, ctx);
  b->header.tag = KK_TAG_LAZY_EVAL;
  b->header.scan_fsize = 0;

  // evaluate
  kk_function_dup(eval_borrow, ctx);
  kk_datatype_t res = kk_datatype_unbox(kk_function_call(kk_box_t, (kk_function_t, kk_box_t, kk_context_t*), eval_borrow, (eval_borrow,kk_block_box(x, ctx),ctx), ctx));

  // TODO: support yielding
  // we need to create some minimal support in the runtime (from `hnd.c`) to have `yield_extend` available.
  if kk_yielding(ctx) {
    kk_fatal_error(ENOTSUP, "yielding from inside a lazy constructor is currently not supported");
    return kk_datatype_null();
  }

  // create an indirection to the result
  kk_block_field_set(b, 0, kk_datatype_box(res));
  b->header.scan_fsize = 1;
  b->header.tag = KK_TAG_INDIRECT;
  return kk_datatype_from_ptr(b,ctx);
}

// Eval a thread-shared value.
static kk_datatype_t kk_lazy_eval_thread_shared(kk_block_t* b, kk_function_t eval_borrow, kk_context_t* ctx) {
  // TODO!
  // The code is the same as for `local` but now atomically.
  // The idea is to duplicate the block `b` and evaluate that (with an rc of 1)
  // while the original `b` is set as a blackhole where the first field points to an atomic blocked list
  // of `kk_context_t` that are blocked on it. Once done, `b` becomes an indirection node.
  // tricky: if we don't have a double word atomic compare-and-swap, we need a way
  // to set it to a blackhole atomically while also initializing the wait-list field.
  // We can use the special `KK_TAG_LAZY_PREP` for that?
  return kk_lazy_eval_local(b, eval_borrow, ctx);
}

kk_decl_export kk_datatype_t kk_datatype_lazy_eval(kk_datatype_t next, kk_function_t eval_borrow, kk_context_t* ctx)
{
  kk_assert(kk_datatype_is_lazy(next, ctx));
  do {
    kk_block_t* b = kk_datatype_as_ptr(next,ctx);
    kk_refcount_t rc = kk_block_refcount(b);
    if (kk_block_has_tag(b, KK_TAG_INDIRECT)) {
      // follow indirection
      next = kk_datatype_unbox(kk_block_field(b, 0));
      if (rc==0) {
        kk_block_free(b, ctx);
      }
      else {
        next = kk_datatype_dup(next, ctx);
        kk_block_decref(b, ctx);
      }
    }
    else {
      if (rc == 0) {
        // evaluate unique value
        next = kk_lazy_eval_unique(b, eval_borrow, ctx);
      }
      else if kk_unlikely(kk_refcount_is_thread_shared(rc)) {
        // evaluate thread shared
        next = kk_lazy_eval_thread_shared(b, eval_borrow, ctx);
      }
      else {
        // evaluate thread local
        next = kk_lazy_eval_local(b, eval_borrow, ctx);
      }
      // TODO: support yielding from `eval_borrow`
      // we need to create some minimal support in the runtime (from `hnd.c`) to have `yield_extend` available.
      if kk_yielding(ctx) {
        kk_fatal_error(ENOTSUP, "yielding from inside a lazy constructor is currently not supported");
        return kk_datatype_null();
      }
    }
    // recursively force the result
  } while(kk_datatype_is_lazy(next, ctx));
  return next;
}
