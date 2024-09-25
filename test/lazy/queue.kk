module queue

import std/os/env
import std/num/random
import std/num/int32

pub value type maybe2<a,b>
  Nothing2
  Just2(justa:a,justb:b)


pub alias rndstate = sfc
alias rndres = sfc-result

fun rnd-step( r : rndstate ) : rndres
  sfc-step(r)

fun rnd-init( s0 : int, s1 : int ) : rndstate
  (sfc-init32(s0.int32,s1.int32))

pub value struct queue<q>
  empty  : q
  snoc   : (q,int) -> pure q
  uncons : q -> pure maybe2<int,q>

fun bench-snoc( i : int, n : int, qi : queue<q>, rs : rndstate, queue : q ) : pure q
  if (i > 0) then
    val step = rnd-step(rs)
    val q' = (qi.snoc)(queue, step.rnd.int)
    bench-snoc(i - 1, n, qi, step.rstate, q')
  else queue

fun bench-uncons( i : int, queue : q, qi : queue<q>, acc = 0 ) : pure int
  if (i > 0) then
    match (qi.uncons)(queue)
      Just2(x, q) -> bench-uncons(i - 1, q, qi, acc + i*x)
      Nothing2    -> throw("uncons failed")
  else acc

fun bench-unconsn( i : int, n : int, queue : q, qi : queue<q>, acc = 0 ) : pure int
  if n > 1 then
    val acc' = bench-uncons(i+1, (qi.snoc)(queue, n), qi, acc)
    bench-unconsn(i, n - 1, queue, qi, acc')
  elif n == 1 then
    bench-uncons(i, queue, qi, acc)
  else acc

pub fun bench( ops : int, n : int, qi : queue<q> ) : pure int
  val q = bench-snoc( ops, n, qi, rnd-init(42,43), qi.empty)
  bench-unconsn( ops, n, q, qi )

pub fun benchmain( qi : queue<q>, ops : int = 1000000) : io ()
  val n = get-args().head("").parse-int.default(1)
  // val ops = 10000000
  val sum = bench(ops / (n + 1), n, qi)
  println("Checksum: " ++ show(sum))
