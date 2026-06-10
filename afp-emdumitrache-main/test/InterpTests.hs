-- | Interpreter tests: positive (correct value) for Phase 0 features.
-- Negative type-checking cases are already covered in TypeCheckTests;
-- here we only test programs that should succeed end-to-end.
module InterpTests where

import Test.Hspec
import Run   (run)
import Value (Value (..))

-- | Assert that the program evaluates to the given value.
interpTest :: String -> Value -> Spec
interpTest input expected =
  it (show input) $
    run input `shouldBe` Right expected

test :: IO ()
test = hspec $ do

  describe "Interpreter Phase 0: expression-level let" $ do
    interpTest "let x = 2 in x + 3"              (VInt 5)
    interpTest "let b = true in b && false"       (VBool False)
    interpTest "let x = 2 in let y = 3 in x + y" (VInt 5)

  describe "Interpreter Phase 0: immutable bindings" $ do
    interpTest "let x = 3; x * x"   (VInt 9)
    interpTest "true && false"       (VBool False)
    interpTest "42"                  (VInt 42)

  describe "Interpreter Phase 0: order of operations" $ do
    interpTest "2 + 3 * 4"    (VInt 14)
    interpTest "4 * 3 + 2"    (VInt 14)
    interpTest "(2 + 3) * 4"  (VInt 20)

  describe "Interpreter Phase 0: mutable reassignment" $ do
    interpTest "let mut x = 0; x = 5; x"            (VInt 5)
    interpTest "let mut x = 0; x = x + 1; x"        (VInt 1)

  describe "Interpreter Phase 0: block scoping" $ do
    -- inner y is invisible outside block; mutation to outer x persists
    interpTest "let mut x = 0; { let y = 5; x = y }; x"  (VInt 5)
    -- block that does not mutate outer scope
    interpTest "let x = 3; { let y = 10 }; x"             (VInt 3)

  describe "Interpreter Phase 0: if / if-else statements" $ do
    interpTest "let mut x = 0; if true { x = 1 }; x"         (VInt 1)
    interpTest "let mut x = 0; if false { x = 1 }; x"        (VInt 0)
    interpTest "let mut x = 0; if x < 1 { x = 1 } else { x = 2 }; x" (VInt 1)
    interpTest "let mut x = 0; if x > 1 { x = 1 } else { x = 2 }; x" (VInt 2)

  describe "Interpreter Phase 0: while loop" $ do
    interpTest "let mut x = 0; while x < 5 { x = x + 1 }; x"  (VInt 5)
    interpTest "let mut y = 0; while y < 3 { y = y + 1 }; y"  (VInt 3)

  describe "Interpreter Phase 0: full control-flow example from spec" $ do
    interpTest
      "let mut x = 0; let mut y = 0; if x < 1 { y = 1 } else { y = 2 }; while y < 5 { y = y + 1 }; y"
      (VInt 5)

  describe "Interpreter Phase 0: functions" $ do
    interpTest "fn double(x: int) -> int { x + x }; double(3)"           (VInt 6)
    interpTest "fn add(x: int, y: int) -> int { x + y }; add(3, 4)"     (VInt 7)
    interpTest "fn no_args() -> int { 42 }; no_args()"                   (VInt 42)
    interpTest "fn isZero(x: int) -> bool { x == 0 }; isZero(0)"        (VBool True)
    interpTest "fn isZero(x: int) -> bool { x == 0 }; isZero(1)"        (VBool False)

  describe "Interpreter Phase 0: mutable parameters" $ do
    interpTest "fn double_in_place(mut x: int) -> int { x = x * 2; x }; double_in_place(3)"
               (VInt 6)

  describe "Interpreter Phase 0: function composition" $ do
    interpTest "fn double(x: int) -> int { x + x }; fn quad(x: int) -> int { double(double(x)) }; quad(3)"
               (VInt 12)

  describe "Interpreter Phase 1: Light literals evaluate correctly" $ do
    interpTest "Red"    VLightRed
    interpTest "Yellow" VLightYellow
    interpTest "Green"  VLightGreen

  describe "Interpreter Phase 1: affine move through let" $ do
    interpTest "let x = Red; x"          VLightRed
    interpTest "let x = Yellow; let y = x; y" VLightYellow

  describe "Interpreter Phase 1: mutable Light reassignment" $ do
    interpTest "let mut x = Red; x = Green; x"   VLightGreen
    interpTest "let mut x = Yellow; x = Red; x"  VLightRed

  describe "Interpreter Phase 1: Light through function" $ do
    interpTest "fn id(s: Light) -> Light { s }; id(Green)" VLightGreen
    interpTest "fn consume(s: Light) -> int { 0 }; consume(Red); 42" (VInt 42)

  describe "Interpreter Phase 2A: list literals and index read" $ do
    interpTest "let x = [10, 20, 30]; x[0]"  (VInt 10)
    interpTest "let x = [10, 20, 30]; x[2]"  (VInt 30)
    interpTest "let x = [true, false]; x[1]" (VBool False)

  describe "Interpreter Phase 2A: push" $ do
    interpTest "let mut x = [1, 2]; x.push(3); x[2]"   (VInt 3)
    interpTest "let mut x = [1]; x.push(2); x.push(3); x[1]" (VInt 2)

  describe "Interpreter Phase 2A: index assignment" $ do
    interpTest "let mut x = [1, 2]; x[0] = 9; x[0]"   (VInt 9)
    interpTest "let mut x = [1, 2]; x[1] = 99; x[1]"  (VInt 99)

  describe "Interpreter Phase 2A: insert" $ do
    interpTest "let mut x = [1, 2]; x.insert(1, 99); x[1]" (VInt 99)
    interpTest "let mut x = [1, 2]; x.insert(0, 99); x[0]" (VInt 99)

  describe "Interpreter Phase 2A: remove" $ do
    interpTest "let mut x = [1, 2, 3]; x.remove(0); x[0]"  (VInt 2)
    interpTest "let mut x = [1, 2, 3]; x.remove(2); x[1]"  (VInt 2)

  describe "Interpreter Phase 2A: spec mutable-list example" $ do
    interpTest
      "let mut list = [1, 2]; list.push(3); list[0] = 4; list.remove(2); let snd = list[1]; list.insert(1, 13); snd"
      (VInt 2)

  describe "Interpreter Phase 2B: int Copy — spec example (use x three times)" $ do
    interpTest "fn f(x: int) -> int { x }; let a = 5; let b = f(a); let c = f(a); a + b + c"
               (VInt 15)
    interpTest "let x = 7; let y = x; let z = x; x + y + z"  (VInt 21)

  describe "Interpreter Phase 2B: bool Copy — use b multiple times" $ do
    interpTest "let b = true; let c = b; let d = b; if b then if c then 1 else 0 else 0"
               (VInt 1)

  describe "Interpreter Phase 2B: Light still non-Copy, list still non-Copy (type-checked)" $ do
    -- these programs reach the interpreter only after type-checking, so we just
    -- verify the copy-primitive path runs correctly end-to-end
    interpTest "let x = 42; x + x"   (VInt 84)
    interpTest "let x = true; if x then 1 else 0"  (VInt 1)

  describe "Interpreter Phase 2C: Ok and Err construction" $ do
    interpTest "Ok(42)"        (VOk (VInt 42))
    interpTest "Err(0)"        (VErr (VInt 0))
    interpTest "Ok(true)"      (VOk (VBool True))

  describe "Interpreter Phase 2C: pair construction" $ do
    interpTest "(1, 2)"        (VPair (VInt 1) (VInt 2))
    interpTest "(5, true)"     (VPair (VInt 5) (VBool True))

  describe "Interpreter Phase 2C: match on Light" $ do
    interpTest "match Red    { Red => 1, Yellow => 2, Green => 3 }"  (VInt 1)
    interpTest "match Yellow { Red => 1, Yellow => 2, Green => 3 }"  (VInt 2)
    interpTest "match Green  { Red => 1, Yellow => 2, Green => 3 }"  (VInt 3)

  describe "Interpreter Phase 2C: match on Result" $ do
    interpTest "let r = Ok(5); match r { Ok(v) => v + 1, Err(e) => 0 }"  (VInt 6)
    interpTest "let r = Err(7); match r { Ok(v) => 0, Err(e) => e + 1 }" (VInt 8)

  describe "Interpreter Phase 2C: match on pair" $ do
    interpTest "let p = (3, 4); match p { (x, y) => x + y }"        (VInt 7)
    interpTest "let p = (10, 3); match p { (a, b) => a - b }"       (VInt 7)

  describe "Interpreter Phase 2C: wildcard pattern" $ do
    interpTest "match Red { r => 42 }"                               (VInt 42)
    interpTest "let p = (1, 2); match p { w => 0 }"                 (VInt 0)

  describe "Interpreter Phase 2C: spec example — safe division via Result" $ do
    interpTest
      "fn safe_div(x: int, y: int) -> Result<int> { if y == 0 then Err(0) else Ok(x / y) }; let r = safe_div(84, 2); match r { Ok(v) => v, Err(e) => e }"
      (VInt 42)

  describe "Interpreter Phase 3A: basic borrow and dereference" $ do
    interpTest "let x = 5; let r = &x; *r"                (VInt 5)
    interpTest "let x = true; let r = &x; *r"             (VBool True)
    interpTest "let x = 5; let r = &x; *r + 1"            (VInt 6)
    interpTest "let x = 5; let r = &x; x + *r"            (VInt 10)

  describe "Interpreter Phase 3A: borrow through function parameter" $ do
    interpTest "fn deref_int(r: &int) -> int { *r }; let x = 42; deref_int(&x)"
               (VInt 42)
    interpTest "fn f(r: &int) -> int { *r + 1 }; let x = 10; f(&x)"
               (VInt 11)

  describe "Interpreter Phase 3A: borrow scope — ref expires in inner block" $ do
    interpTest "let x = 5; { let r = &x }; x"             (VInt 5)
    interpTest "let mut x = 5; { let r = &x }; x = 10; x" (VInt 10)

  describe "Interpreter Phase 3B: basic mutable borrow and dereference" $ do
    interpTest "let mut x = 5; let b = &mut x; *b"        (VInt 5)
    interpTest "let mut x = true; let b = &mut x; *b"     (VBool True)
    interpTest "let mut x = Red; let b = &mut x; *b"      VLightRed

  describe "Interpreter Phase 3B: SDerefAssign writes through mutable reference" $ do
    interpTest "let mut x = 5; let b = &mut x; *b = 10; x"      (VInt 10)
    interpTest "let mut x = Red; let b = &mut x; *b = Green; *b" VLightGreen

  describe "Interpreter Phase 3B: place-expression allows double deref of &mut" $ do
    interpTest "fn f(b: &mut int) -> int { *b + *b }; let mut x = 21; f(&mut x)"
               (VInt 42)

  describe "Interpreter Phase 3B: set_red spec example" $ do
    interpTest "fn set_red(mut light: &mut Light) -> () { *light = Red }; let mut l = Green; set_red(&mut l); l"
               VLightRed

  describe "Interpreter Phase 3C: NLL — borrow expires at last use" $ do
    interpTest "let mut x = 5; let r = &x; *r; x = 10; x"     (VInt 10)
    interpTest "let mut x = Red; let r = &x; *r; x = Green; x" VLightGreen

  describe "Interpreter Phase 3C: NLL — unused borrow allows immediate reuse" $ do
    interpTest "let mut x = 5; let r = &x; x = 10; x"          (VInt 10)
    interpTest "let x = Red; let r = &x; x"                    VLightRed

  describe "Interpreter Phase 3C: NLL — mutable borrow expires at last use" $ do
    interpTest "let mut x = 5; let b = &mut x; *b; x = 20; x"  (VInt 20)
    interpTest "let mut x = Red; let b = &mut x; *b = Green; x = Red; x" VLightRed

  describe "Interpreter Phase 4A: lifetime-generic function returns reference" $ do
    interpTest "fn id_ref<'a>(x: &'a int) -> &'a int { x }; let y = 5; let r = id_ref(&y); *r"
               (VInt 5)
    interpTest "fn id_ref<'a>(x: &'a Light) -> &'a Light { x }; let c = Red; let r = id_ref(&c); *r"
               VLightRed
    interpTest "fn first<'a, 'b>(x: &'a int, y: &'b int) -> &'a int { x }; let a = 3; let b = 4; let r = first(&a, &b); *r"
               (VInt 3)

  describe "Interpreter Phase 4A: lifetime function used for dereferencing" $ do
    interpTest "fn deref_lt<'a>(x: &'a int) -> int { *x }; let y = 42; deref_lt(&y)"
               (VInt 42)
    interpTest "fn id_ref<'a>(x: &'a int) -> &'a int { x }; let y = 7; let r = id_ref(&y); *r + y"
               (VInt 14)

  describe "Interpreter Phase 4B: spawn runs block synchronously" $ do
    interpTest "spawn { }; 42"                           (VInt 42)
    interpTest "let x = 5; spawn { let y = x }; x"      (VInt 5)
    interpTest "let b = true; spawn { let c = b }; b"   (VBool True)
    interpTest "let mut x = 0; spawn { x = 1 }; x"      (VInt 1)
