struct num<a>
  plus : (a,a) -> a
  zero : a

fun num/(+)( x : a, y : a, ?num : num<a> ) : a
  (?num.plus)(x,y)

fun list/(+)( xs : list<a>, ys : list<a>, ?num : num<a> ) : a
  zipwith(xs,ys,num/(+)).foldl(num.zero,num/(+))


val bool/num : num<bool> = Num( xor, False )
val int/num : num<int>   = Num( int/(+), 0 )


pub fun main()
   ([1] + [2], True + False).println