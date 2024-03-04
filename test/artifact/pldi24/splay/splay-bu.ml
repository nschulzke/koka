open Int32

type tree =
| Leaf
| Node of tree * int * tree;;

type zipper =
| Done
| NodeR of tree * int * zipper
| NodeL of zipper * int * tree;;


let rec splay z l x r =
  match z with
  | Done -> Node(l,x,r)
  | NodeR (zl,zx,zz) -> begin match zz with
      | Done -> Node (Node (zl,zx,l),x,r)
      | NodeR (zzl,zzx,zzz) -> splay zzz (Node (Node (zzl,zzx,zl),zx,l)) x r
      | NodeL (zzz,zzx,zzr) -> splay zzz (Node(zl,zx,l)) x (Node(r,zzx,zzr)) end
  | NodeL(zz,zx,zr) -> begin match zz with
      | Done -> Node (l,x,Node(r,zx,zr))
      | NodeR (zzl,zzx,zzz) -> splay zzz (Node(zzl,zzx,l)) x (Node(r,zx,zr))
      | NodeL (zzz,zzx,zzr) -> splay zzz l x (Node(r,zx,(Node(zr,zzx,zzr)))) end;;

let rec accessz t k z =
  match t with
  | Node (l,x,r) -> if (x < k) then accessz r k (NodeR (l,x,z))
                    else if (x > k) then accessz l k (NodeL (z,x,r))
                    else splay z l x r
  | Leaf         -> splay z Leaf k Leaf;;

let access t k = accessz t k Done;;  


(* helpers *)

let rec sumacc t acc = 
  match t with
  | Node (l,x,r) -> sumacc r (sumacc l (acc+x))
  | Leaf         -> acc;;

let sum t = sumacc t 0;;

let imin x y = if (x <= y) then x else y;;
let imax x y = if (x >= y) then x else y;;

let rec minheight t = 
  match t with
  | Node (l,x,r) -> 1 + imin (minheight l) (minheight r)
  | Leaf             -> 0;;

let rec maxheight t = 
  match t with
  | Node (l,x,r) -> 1 + imax (maxheight l) (maxheight r)
  | Leaf             -> 0;;

let top t = 
  match t with
  | Node (l,x,r) -> x
  | Leaf             -> 0;;

type sfc =
| Sfc of int32 * int32 * int32 * int32;;

let rotl i n =
  logor (shift_left i n) (shift_right_logical i (32 - n));;

let sfc_step sfc =
  match sfc with
  | Sfc (x,y,z,cnt) -> 
    let res = add x  (add y cnt) in
    (to_int res,Sfc (logxor y (shift_right_logical y 9),
                      add z (shift_left z 3),
                      add (rotl z 21)  res,
                      add cnt one ));;

let sfc_init seed1 seed2 =
  let s = ref (Sfc (zero,of_int seed1, of_int seed2,one)) in
  for i = 1 to 12 do
    let (_,s1) = sfc_step !s in
    s := s1
  done;
  !s;;


let modE i j =
  let m = i mod j in
  if (i < 0 && m < 0) then (if (j < 0) then m - j else m + j)
  else m;;

let test n iter =
  let t = ref Leaf in
  let s = ref (sfc_init 42 43) in
  for i = 1 to iter do
    for j = 1 to n do
      let (x,s1) = sfc_step !s in
      s := s1;
      t := access !t (modE x n)
    done;
  done;
  let (final,_) = sfc_step !s in
  (!t,final);;

let main n = 
  let (t,final) = test (if n == 0 then 100000 else n) 100 in
  Printf.printf "sum: %d, height: %d/%d, top: %d, final access: %d\n" (sum t) (maxheight t) (minheight t) (top t) final;;


main (int_of_string Sys.argv.(1));; 
