import queue
import std/core/undiv

type stream<a>
  SNil
  SCons( head : a, tail : stream<a> )
  SAppRev( pre : stream<a>, post : list<a> )
  SIndirect( s : stream<a> )                  // generated (must end in "Indirect")

fun sreverse-acc( xs : list<a>, acc : stream<a> ) : stream<a>
  match xs
    Cons(x,xx) -> sreverse-acc(xx, SCons(x,acc))
    Nil        -> acc

fun sreverse( xs : list<a> ) : stream<a>
  sreverse-acc(xs,SNil)


extern lazy-whnf-target(target : a) : ()
  ""
extern lazy-update(target : a, x : a) : a
  c inline "#1"


// todo:
extern lazy-atomic-blackhole(^target : a) : bool
  inline "true"
extern lazy-atomic-update(target : a, x : a) : a
  ""
extern lazy-atomic-wait(target : a) : a
  ""
extern datatype-is-thread-local( ^x : a ) : bool
  inline "true"
extern datatype-copy( ^x : a ) : a
  ""

// this should be generated; lazy-update is always inserted at tail-position.
// If the argument is not a syntactic non-lazy constructor a recursive call to `stream-whnf` is added as well. (case `(A)`)
// If the argument is a singleton (`SNil`), larger, or unknown (`sreverse(post)`),
// an indirection is automatically inserted (`SIndirect`)
noinline fun stream-whnf( s : stream<a> ) : _ stream<a>
  lazy-whnf-target(s)
  match s
    SAppRev( pre, post )
      -> match stream-force(pre)
           // SNil        -> stream-whnf(lazy-update(s,sreverse(post)))  // (A)
           SNil        -> match post
                            Cons(x,xx) -> lazy-update(s,SCons(x,sreverse(xx)))
                            Nil        -> lazy-update(s,SNil)
           SCons(x,xx) -> lazy-update(s,SCons(x,SAppRev(xx,post)))
           _           -> lazy-update(s,SNil) // this cannot happen; todo: fix partial check
    // generated
    SIndirect(ind)
      -> stream-whnf(pretend-decreasing(ind))
    _ -> s

noinline fun stream-atomic-whnf( s : stream<a> ) : _ stream<a>
  if lazy-atomic-blackhole(s)
    then lazy-atomic-update(s,SIndirect(stream-whnf(datatype-copy(s))))
    else stream-whnf(lazy-atomic-wait(s))


fun stream-force( s : stream<a> ) : _ stream<a>
  stream-whnf(s)
  // if datatype-is-thread-local(s)
  //   then stream-whnf(s) else stream-atomic-whnf(s)


struct bqueue<a>
  front : stream<a>
  front-len : int
  rear : list<a>
  rear-len : int

val bankers/empty = Bqueue( SNil, 0, Nil, 0 )

fun is-empty( ^q : bqueue<a> ) : bool
  q.front-len==0

fun size( ^q : bqueue<a> ) : int
  q.front-len + q.rear-len


fip(1) fun check( q : bqueue<a> ) : bqueue<a>
  match q
    Bqueue(front, front-len, rear, rear-len) ->
      if (front-len >= rear-len)
       then Bqueue(front, front-len, rear, rear-len)
       else Bqueue( SAppRev(front,rear), front-len + rear-len, Nil, 0)

fip(2) fun snoc( q : bqueue<a>, x : a ) : bqueue<a>
  match q
    Bqueue(front,front-len,rear,rear-len) ->
      Bqueue(front, front-len, Cons(x,rear), rear-len+1).check

fbip(2) fun uncons( Bqueue(front,front-len,rear,rear-len) : bqueue<a> ) : div maybe2<a,bqueue<a>>
  match stream-force(front)
    SCons(x,xx) -> Just2(x, Bqueue(xx,front-len - 1,rear,rear-len).check)
    SNil        -> Nothing2
    _           -> Nothing2 // todo: fix partial check

pub fun main()
  benchmain(Queue(bankers/empty, snoc, uncons))
