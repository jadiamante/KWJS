(module
  (memory (export "memory") 64)

  ;; CRC-32 (IEEE 802.3) sobre [p, p+n)
  (func (export "crc32") (param $p i32) (param $n i32) (result i32)
    (local $c i32) (local $i i32) (local $k i32)
    (local.set $c (i32.const -1))
    (block $done
      (loop $bytes
        (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
        (local.set $c (i32.xor (local.get $c) (i32.load8_u (i32.add (local.get $p) (local.get $i)))))
        (local.set $k (i32.const 8))
        (loop $bits
          (local.set $c
            (select
              (i32.xor (i32.shr_u (local.get $c) (i32.const 1)) (i32.const 0xEDB88320))
              (i32.shr_u (local.get $c) (i32.const 1))
              (i32.and (local.get $c) (i32.const 1))))
          (local.set $k (i32.sub (local.get $k) (i32.const 1)))
          (br_if $bits (local.get $k)))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $bytes)))
    (i32.xor (local.get $c) (i32.const -1)))

  ;; Conjunto de Mandelbrot: escribe u32 (iteraciones) por píxel en $out
  (func (export "mandel") (param $out i32) (param $w i32) (param $h i32) (param $maxit i32)
    (local $x i32) (local $y i32) (local $it i32)
    (local $cr f64) (local $ci f64) (local $zr f64) (local $zi f64) (local $t f64)
    (block $ydone
      (loop $yl
        (br_if $ydone (i32.ge_u (local.get $y) (local.get $h)))
        (local.set $x (i32.const 0))
        (block $xdone
          (loop $xl
            (br_if $xdone (i32.ge_u (local.get $x) (local.get $w)))
            (local.set $cr (f64.add (f64.const -2.2) (f64.mul (f64.const 3.2) (f64.div (f64.convert_i32_u (local.get $x)) (f64.convert_i32_u (local.get $w))))))
            (local.set $ci (f64.add (f64.const -1.2) (f64.mul (f64.const 2.4) (f64.div (f64.convert_i32_u (local.get $y)) (f64.convert_i32_u (local.get $h))))))
            (local.set $zr (f64.const 0))
            (local.set $zi (f64.const 0))
            (local.set $it (i32.const 0))
            (block $idone
              (loop $il
                (br_if $idone (i32.ge_u (local.get $it) (local.get $maxit)))
                (br_if $idone (f64.gt (f64.add (f64.mul (local.get $zr) (local.get $zr)) (f64.mul (local.get $zi) (local.get $zi))) (f64.const 4)))
                (local.set $t (f64.add (f64.sub (f64.mul (local.get $zr) (local.get $zr)) (f64.mul (local.get $zi) (local.get $zi))) (local.get $cr)))
                (local.set $zi (f64.add (f64.mul (f64.const 2) (f64.mul (local.get $zr) (local.get $zi))) (local.get $ci)))
                (local.set $zr (local.get $t))
                (local.set $it (i32.add (local.get $it) (i32.const 1)))
                (br $il)))
            (i32.store
              (i32.add (local.get $out) (i32.shl (i32.add (i32.mul (local.get $y) (local.get $w)) (local.get $x)) (i32.const 2)))
              (local.get $it))
            (local.set $x (i32.add (local.get $x) (i32.const 1)))
            (br $xl)))
        (local.set $y (i32.add (local.get $y) (i32.const 1)))
        (br $yl))))

  ;; canal final (0..255) tras saturación, contraste y brillo
  (func $ch (param $v f32) (param $l f32) (param $s f32) (param $c f32) (param $br f32) (result i32)
    (local $x f32)
    (local.set $x
      (f32.add
        (f32.add
          (f32.mul
            (f32.sub
              (f32.add (local.get $l) (f32.mul (f32.sub (local.get $v) (local.get $l)) (local.get $s)))
              (f32.const 0.5))
            (local.get $c))
          (f32.const 0.5))
        (local.get $br)))
    (local.set $x (f32.max (f32.const 0) (f32.min (f32.const 1) (local.get $x))))
    (i32.trunc_f32_u (f32.add (f32.mul (local.get $x) (f32.const 255)) (f32.const 0.5))))

  ;; brillo (-1..1), contraste (0..2), saturación (0..2) sobre n píxeles RGBA
  (func (export "adjust") (param $p i32) (param $n i32) (param $br f32) (param $c f32) (param $s f32)
    (local $i i32) (local $a i32) (local $r f32) (local $g f32) (local $b f32) (local $l f32)
    (block $done
      (loop $px
        (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
        (local.set $a (i32.add (local.get $p) (i32.shl (local.get $i) (i32.const 2))))
        (local.set $r (f32.div (f32.convert_i32_u (i32.load8_u (local.get $a))) (f32.const 255)))
        (local.set $g (f32.div (f32.convert_i32_u (i32.load8_u offset=1 (local.get $a))) (f32.const 255)))
        (local.set $b (f32.div (f32.convert_i32_u (i32.load8_u offset=2 (local.get $a))) (f32.const 255)))
        (local.set $l
          (f32.add
            (f32.add (f32.mul (local.get $r) (f32.const 0.299)) (f32.mul (local.get $g) (f32.const 0.587)))
            (f32.mul (local.get $b) (f32.const 0.114))))
        (i32.store8 (local.get $a) (call $ch (local.get $r) (local.get $l) (local.get $s) (local.get $c) (local.get $br)))
        (i32.store8 offset=1 (local.get $a) (call $ch (local.get $g) (local.get $l) (local.get $s) (local.get $c) (local.get $br)))
        (i32.store8 offset=2 (local.get $a) (call $ch (local.get $b) (local.get $l) (local.get $s) (local.get $c) (local.get $br)))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $px))))

  (func (export "gray") (param $p i32) (param $n i32)
    (local $i i32) (local $a i32) (local $l i32)
    (block $done
      (loop $px
        (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
        (local.set $a (i32.add (local.get $p) (i32.shl (local.get $i) (i32.const 2))))
        (local.set $l
          (i32.div_u
            (i32.add
              (i32.add
                (i32.mul (i32.load8_u (local.get $a)) (i32.const 299))
                (i32.mul (i32.load8_u offset=1 (local.get $a)) (i32.const 587)))
              (i32.mul (i32.load8_u offset=2 (local.get $a)) (i32.const 114)))
            (i32.const 1000)))
        (i32.store8 (local.get $a) (local.get $l))
        (i32.store8 offset=1 (local.get $a) (local.get $l))
        (i32.store8 offset=2 (local.get $a) (local.get $l))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $px))))

  (func (export "invert") (param $p i32) (param $n i32)
    (local $i i32) (local $a i32)
    (block $done
      (loop $px
        (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
        (local.set $a (i32.add (local.get $p) (i32.shl (local.get $i) (i32.const 2))))
        (i32.store8 (local.get $a) (i32.sub (i32.const 255) (i32.load8_u (local.get $a))))
        (i32.store8 offset=1 (local.get $a) (i32.sub (i32.const 255) (i32.load8_u offset=1 (local.get $a))))
        (i32.store8 offset=2 (local.get $a) (i32.sub (i32.const 255) (i32.load8_u offset=2 (local.get $a))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $px))))

  (func $min255 (param $v i32) (result i32)
    (select (i32.const 255) (local.get $v) (i32.gt_u (local.get $v) (i32.const 255))))

  (func (export "sepia") (param $p i32) (param $n i32)
    (local $i i32) (local $a i32) (local $r i32) (local $g i32) (local $b i32)
    (block $done
      (loop $px
        (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
        (local.set $a (i32.add (local.get $p) (i32.shl (local.get $i) (i32.const 2))))
        (local.set $r (i32.load8_u (local.get $a)))
        (local.set $g (i32.load8_u offset=1 (local.get $a)))
        (local.set $b (i32.load8_u offset=2 (local.get $a)))
        (i32.store8 (local.get $a)
          (call $min255 (i32.div_u (i32.add (i32.add (i32.mul (local.get $r) (i32.const 393)) (i32.mul (local.get $g) (i32.const 769))) (i32.mul (local.get $b) (i32.const 189))) (i32.const 1000))))
        (i32.store8 offset=1 (local.get $a)
          (call $min255 (i32.div_u (i32.add (i32.add (i32.mul (local.get $r) (i32.const 349)) (i32.mul (local.get $g) (i32.const 686))) (i32.mul (local.get $b) (i32.const 168))) (i32.const 1000))))
        (i32.store8 offset=2 (local.get $a)
          (call $min255 (i32.div_u (i32.add (i32.add (i32.mul (local.get $r) (i32.const 272)) (i32.mul (local.get $g) (i32.const 534))) (i32.mul (local.get $b) (i32.const 131))) (i32.const 1000))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $px))))

  ;; Convolución 3x3 (RGB; alfa se copia). $k apunta a 9 f32 en orden de filas.
  (func (export "conv3") (param $src i32) (param $dst i32) (param $w i32) (param $h i32) (param $k i32)
    (local $x i32) (local $y i32) (local $c i32) (local $j i32) (local $sx i32) (local $sy i32)
    (local $acc f32) (local $o i32)
    (block $ydone
      (loop $yl
        (br_if $ydone (i32.ge_u (local.get $y) (local.get $h)))
        (local.set $x (i32.const 0))
        (block $xdone
          (loop $xl
            (br_if $xdone (i32.ge_u (local.get $x) (local.get $w)))
            (local.set $o (i32.add (local.get $dst) (i32.shl (i32.add (i32.mul (local.get $y) (local.get $w)) (local.get $x)) (i32.const 2))))
            (i32.store8 offset=3 (local.get $o)
              (i32.load8_u offset=3 (i32.add (local.get $src) (i32.shl (i32.add (i32.mul (local.get $y) (local.get $w)) (local.get $x)) (i32.const 2)))))
            (local.set $c (i32.const 0))
            (block $cdone
              (loop $cl
                (br_if $cdone (i32.ge_u (local.get $c) (i32.const 3)))
                (local.set $acc (f32.const 0))
                (local.set $j (i32.const 0))
                (block $jdone
                  (loop $jl
                    (br_if $jdone (i32.ge_u (local.get $j) (i32.const 9)))
                    (local.set $sx (i32.add (local.get $x) (i32.sub (i32.rem_u (local.get $j) (i32.const 3)) (i32.const 1))))
                    (local.set $sy (i32.add (local.get $y) (i32.sub (i32.div_u (local.get $j) (i32.const 3)) (i32.const 1))))
                    (local.set $sx (select (i32.const 0) (local.get $sx) (i32.lt_s (local.get $sx) (i32.const 0))))
                    (local.set $sx (select (i32.sub (local.get $w) (i32.const 1)) (local.get $sx) (i32.ge_s (local.get $sx) (local.get $w))))
                    (local.set $sy (select (i32.const 0) (local.get $sy) (i32.lt_s (local.get $sy) (i32.const 0))))
                    (local.set $sy (select (i32.sub (local.get $h) (i32.const 1)) (local.get $sy) (i32.ge_s (local.get $sy) (local.get $h))))
                    (local.set $acc
                      (f32.add (local.get $acc)
                        (f32.mul
                          (f32.load (i32.add (local.get $k) (i32.shl (local.get $j) (i32.const 2))))
                          (f32.convert_i32_u
                            (i32.load8_u
                              (i32.add
                                (i32.add (local.get $src) (i32.shl (i32.add (i32.mul (local.get $sy) (local.get $w)) (local.get $sx)) (i32.const 2)))
                                (local.get $c)))))))
                    (local.set $j (i32.add (local.get $j) (i32.const 1)))
                    (br $jl)))
                (i32.store8
                  (i32.add (local.get $o) (local.get $c))
                  (i32.trunc_f32_u (f32.add (f32.max (f32.const 0) (f32.min (f32.const 255) (local.get $acc))) (f32.const 0.5))))
                (local.set $c (i32.add (local.get $c) (i32.const 1)))
                (br $cl)))
            (local.set $x (i32.add (local.get $x) (i32.const 1)))
            (br $xl)))
        (local.set $y (i32.add (local.get $y) (i32.const 1)))
        (br $yl))))
)
