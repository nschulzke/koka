import std/core/undiv

type llist<a>
  LNil
  LCons( head : a, tail : llist<a> )
  LApp( pre : llist<a>, post : llist<a> )
  LIndirect( l : llist<a> )

extern lazy-whnf-target(target : a) : ()
  ""
extern lazy-update(target : a, x : a) : a
  c inline "#1"

// this should be generated
fun llist-whnf( xs : llist<a> ) : _ llist<a>
  lazy-whnf-target(xs)
  match xs
    // LApp( LNil, post )        -> post
    // LApp( LCons(x,xx), post ) -> LCons(x,LApp(xx,post))
    LApp(pre,post) ->
      match llist-force(pre)
        LNil        -> lazy-update(xs,post)
        LCons(x,xx) -> lazy-update(xs,LCons(x,LApp(xx,post)))
        _           -> lazy-update(xs,pre)            // fix partial check
    // generated
    LIndirect(l)
      -> llist-whnf(pretend-decreasing(l))
    _ -> xs

// good code, but dup/drop's the static `eval` function.
// we could do better by generating the test explicitly (as in `llist-force2`) but specialized.
inline fun llist-force( xs : llist<a> ) : _ llist<a>
  llist-whnf(xs)

fun llist(n : int) : llist<int>
  fold(n,LNil, fn(i,acc) LCons(i,acc))

fun list( xs : llist<a> ) : _ list<a>
  match llist-force(xs)
    LNil -> Nil
    LCons(x,xx) -> Cons(x, xx.list)
    _    -> Nil  // should not be needed

fun map( xs : llist<a>, f : a -> <div|e> b ) : <div|e> llist<b>
  match llist-force(xs)
    LNil -> LNil
    LCons(x,xx) -> LCons(f(x), xx.map(f))
    _    -> LNil  // should not be needed


fun test1()
  LApp(llist(3),llist(3)).map(inc).list.show

