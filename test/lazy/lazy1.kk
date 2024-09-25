type llist<a>
  LNil
  LCons( head : a, tail : llist<a> )
  LApp( pre : llist<a>, post : llist<a> )

// this should be generated
fun llist-eval( xs : llist<a> ) : llist<a>
  match xs
    LApp( LNil, post )        -> post
    LApp( LCons(x,xx), post ) -> LCons(x,LApp(xx,post))
    _ -> xs

// good code, but dup/drop's the static `eval` function.
// we could do better by generating the test explicitly (as in `llist-force2`) but specialized.
inline fun llist-force( xs : llist<a> ) : div llist<a>
  force(xs,llist-eval)

// doesn't work well due to boxing which makes `xs` dup'd.
// if we generate specialized functions for each type this should work?
inline fun llist-force2( xs : llist<a> ) : div llist<a>
  match is-lazy(xs)
    False -> id(xs)
    True  -> lazy-eval(xs,llist-eval)


fun llist(n : int) : llist<int>
  fold(n,LNil, fn(i,acc) LCons(i,acc))

fun list( xs : llist<a> ) : div list<a>
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

