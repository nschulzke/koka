#pragma once
#ifndef KK_LAZY_H
#define KK_LAZY_H
/*---------------------------------------------------------------------------
  Copyright 2024, Microsoft Research, Daan Leijen, Anton Lorenzen

  This is free software; you can redistribute it and/or modify it under the
  terms of the Apache License, Version 2.0. A copy of the License can be
  found in the LICENSE file at the root of this distribution.
---------------------------------------------------------------------------*/

/*---------------------------------------------------------------------------------------------------------------
  Besides for first-class constructor contexts and stackless freeing, we use the field idx too for lazy values
  This is ok since lazy values cannot be in a context,
  and if they are freed it is no longer relevant (and can be overwritten)
-------------------------------------------------------------------------------------------------------------*/

static inline bool kk_block_is_lazy(kk_block_t* b) {
  return kk_tag_is_lazy(kk_block_tag(b));
}

static inline bool kk_block_is_lazy_or_special(kk_block_t* b) {
  return (kk_block_tag(b) >= KK_TAG_LAZY); // for typed data, this is a faster test if the constructor is lazy
}

static inline bool kk_block_is_blackhole(kk_block_t* b) {
  return kk_block_has_tag(b, KK_TAG_LAZY_EVAL);
}

static inline bool kk_datatype_is_lazy( kk_datatype_t d, kk_context_t* ctx) {
  if (!kk_datatype_is_ptr(d)) return false;
  return kk_block_is_lazy(kk_datatype_as_ptr(d,ctx));
}

static inline bool kk_datatype_is_lazy_or_special( kk_datatype_t d, kk_context_t* ctx) {
  if (!kk_datatype_is_ptr(d)) return false;
  return kk_block_is_lazy_or_special(kk_datatype_as_ptr(d,ctx));
}

// `forall<e,a> ( x : a, eval: a -> e a) -> e a`. For now `e` must be at most `<div>` as we
// don't support yielding from the lazy constructor function (yet).
kk_decl_export kk_datatype_t kk_datatype_lazy_eval(kk_datatype_t d, kk_function_t eval, kk_context_t* ctx);

// todo: for efficiency, we assume `eval` is static (and thus needs no drop)
static inline kk_datatype_t kk_datatype_lazy_force(kk_datatype_t d, kk_function_t eval, kk_context_t* ctx) {
  if (!kk_datatype_is_lazy_or_special(d, ctx)) {  // assume used on typed lazy data (so we can use the quick test)
    kk_function_static_drop(eval,ctx);
    return d;
  }
  else {
    kk_assert(kk_datatype_is_lazy(d,ctx));
    return kk_datatype_lazy_eval(d, eval, ctx);
  }
}


static inline bool kk_is_lazy( kk_box_t d, kk_context_t* ctx) {
  return kk_datatype_is_lazy_or_special(kk_datatype_unbox(d),ctx);
}

static inline kk_box_t kk_lazy_eval( kk_box_t d, kk_function_t eval, kk_context_t* ctx) {
  return kk_datatype_box(kk_datatype_lazy_eval(kk_datatype_unbox(d),eval,ctx));
}

static inline kk_box_t kk_lazy_force(kk_box_t d, kk_function_t eval, kk_context_t* ctx) {
  return kk_datatype_box(kk_datatype_lazy_force(kk_datatype_unbox(d),eval,ctx));
}


static inline kk_datatype_t kk_lazy_indirect(kk_datatype_t target, kk_datatype_t val, kk_context_t* ctx) {
  kk_block_t* b = kk_datatype_as_ptr(target,ctx);
  if kk_likely(kk_block_is_unique(b)) {
    kk_block_free(b,ctx);
    return val;
  }
  else {
    kk_header_init(&b->header,1 /* scan */, 1 /* cpath */, KK_TAG_LAZY_IND);
    kk_block_field_set(b,0,kk_datatype_box(val));
    return target;
  }
}

#endif // KK_LAZY_H
