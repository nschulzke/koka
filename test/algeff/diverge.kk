// --------------------------------------------------------
//
// --------------------------------------------------------

div effect diverge {
  fun fix( f : (a -> diverge b, a) -> diverge b, x : a ) : b
}

val diverge = handler {
  return x  -> x
  fix(f,x)    -> resume( f(fn(y){ fix(f,y) }, x) )
}

