// --------------------------------------------------------
//
// --------------------------------------------------------

div effect diverge
  fun fix( f : (a -> <handled<diverge>> b, a) -> <handled<diverge>> b, x : a ) : b

effect test
  fun op( f : (int -> test int) -> int ) : int

fun test()
  1

// val diverge = handler
//  fun fix(f,x) resume( f(fn(y){ fix(f,y) }, x) )


