-- | Type-checker tests: positive (accepts), negative (rejects), and
-- error-message tests (checks the error text) for Phase 0 features.
module TypeCheckTests where

import Test.Hspec
import Data.Either (isLeft)

import Run       (infertype)
import Lang.Abs  (Type (..))

-- Assert that the program type-checks to the given type.
tcTest :: String -> Type -> Spec
tcTest input expected =
  it (show input) $
    infertype input `shouldBe` Right expected

-- Assert that the program is rejected by the type checker.
tcErrorTest :: String -> Spec
tcErrorTest input =
  it (show input ++ " [should fail]") $
    infertype input `shouldSatisfy` isLeft

-- Assert that the type error message contains the given substring.
tcMsgTest :: String -> String -> Spec
tcMsgTest input substr =
  it (show input ++ " [error contains " ++ show substr ++ "]") $
    case infertype input of
      Left err -> err `shouldContain` substr
      Right _  -> expectationFailure "Expected a type error"

test :: IO ()
test = hspec $ do

  describe "TypeChecker Phase 0: expression-level let (still supported)" $ do
    tcTest "let x = 2 in x + 3"          TInt
    tcTest "let b = true in b && false"   TBool
    tcTest "let x = 2 in let y = 3 in x + y" TInt

  describe "TypeChecker Phase 0: immutable bindings" $ do
    tcTest "let x = 3; x * x"             TInt
    tcTest "let x = true; x"              TBool
    tcTest "true && false"                TBool
    tcTest "42"                           TInt

  describe "TypeChecker Phase 0: mutable bindings and reassignment" $ do
    tcTest "let mut x = 0; x = 5; x"     TInt
    tcTest "let mut x = true; x = false; x" TBool

  describe "TypeChecker Phase 0: immutable reassignment is rejected" $ do
    tcErrorTest "let x = 0; x = 5; x"
    tcMsgTest   "let x = 0; x = 5; x"   "immutable"

  describe "TypeChecker Phase 0: block scoping" $ do
    tcTest "let mut x = 0; { let y = 5; x = y }; x"  TInt
    tcErrorTest "{ let y = 5 }; y"

  describe "TypeChecker Phase 0: if / if-else statements" $ do
    tcTest "let mut x = 0; if x < 1 { x = 1 }; x"         TInt
    tcTest "let mut x = 0; if x < 1 { x = 1 } else { x = 2 }; x" TInt
    tcErrorTest "if 42 { }; 0"
    tcMsgTest   "if 42 { }; 0"   "bool"

  describe "TypeChecker Phase 0: while loop" $ do
    tcTest "let mut x = 0; while x < 5 { x = x + 1 }; x" TInt
    tcErrorTest "while 42 { }; 0"

  describe "TypeChecker Phase 0: functions" $ do
    tcTest "fn double(x: int) -> int { x + x }; double(3)"                    TInt
    tcTest "fn add(x: int, y: int) -> int { x + y }; add(3, 4)"              TInt
    tcTest "fn double_in_place(mut x: int) -> int { x = x * 2; x }; double_in_place(3)" TInt
    tcTest "fn no_args() -> int { 42 }; no_args()"                            TInt
    tcTest "fn isZero(x: int) -> bool { x == 0 }; isZero(0)"                 TBool

  describe "TypeChecker Phase 0: function error cases" $ do
    tcErrorTest "fn f(x: int) -> int { x }; f(true)"
    tcMsgTest   "fn f(x: int) -> int { x }; f(true)"   "bool"
    tcErrorTest "fn f(x: int) -> int { x }; f(1, 2)"
    tcMsgTest   "fn f(x: int) -> int { x }; f(1, 2)"   "argument"
    tcErrorTest "fn f(x: int) -> bool { x }; f(1)"
    tcMsgTest   "fn f(x: int) -> bool { x }; f(1)"     "bool"
    tcErrorTest "undeclared"
    tcMsgTest   "undeclared"   "not bound"

  describe "TypeChecker Phase 0: type mismatches" $ do
    tcErrorTest "true + 1"
    tcErrorTest "1 && true"
    tcErrorTest "let x = 0; x + true"

  describe "TypeChecker Phase 1: Light literal types" $ do
    tcTest "Red"    TLight
    tcTest "Yellow" TLight
    tcTest "Green"  TLight

  describe "TypeChecker Phase 1: Light bindings (affine, move on read)" $ do
    tcTest "let x = Red; x"    TLight
    tcTest "let mut x = Red; x" TLight
    tcTest "let mut x = Red; x = Green; x" TLight

  describe "TypeChecker Phase 1: use-after-move is rejected" $ do
    tcErrorTest "let x = Red; let y = x; x"
    tcMsgTest   "let x = Red; let y = x; x"  "moved"
    tcErrorTest "fn f(s: Light) -> Light { s }; let x = Red; f(x); x"
    tcMsgTest   "fn f(s: Light) -> Light { s }; let x = Red; f(x); x" "moved"

  describe "TypeChecker Phase 1: int/bool remain copyable (can read twice)" $ do
    tcTest "let x = 42; let y = x; x + y"       TInt
    tcTest "let b = true; let c = b; b && c"     TBool

  describe "TypeChecker Phase 1: Light in function parameter and return" $ do
    tcTest "fn id(s: Light) -> Light { s }; id(Red)" TLight
    tcTest "fn consume(s: Light) -> int { 0 }; consume(Red); 1" TInt

  describe "TypeChecker Phase 2A: list literals and element type inference" $ do
    tcTest "let x = [1, 2, 3]; x"         (TList TInt)
    tcTest "let x = [true, false]; x"     (TList TBool)
    tcTest "let x = [1]; x[0]"            TInt
    tcErrorTest "[]"
    tcMsgTest   "[]"   "empty"

  describe "TypeChecker Phase 2A: immutable list - read allowed, mutation rejected" $ do
    tcTest    "let x = [1, 2]; x[1]"     TInt
    tcErrorTest "let x = [1, 2]; x.push(3); x"
    tcMsgTest   "let x = [1, 2]; x.push(3); x"  "immutable"
    tcErrorTest "let x = [1, 2]; x[0] = 9; x"
    tcMsgTest   "let x = [1, 2]; x[0] = 9; x"   "immutable"
    tcErrorTest "let x = [1, 2]; x.insert(0, 9); x"
    tcMsgTest   "let x = [1, 2]; x.insert(0, 9); x"  "immutable"
    tcErrorTest "let x = [1, 2]; x.remove(0); x"
    tcMsgTest   "let x = [1, 2]; x.remove(0); x"     "immutable"

  describe "TypeChecker Phase 2A: mutable list - all operations allowed" $ do
    tcTest "let mut x = [1, 2]; x.push(3); x"          (TList TInt)
    tcTest "let mut x = [1, 2]; x[0] = 9; x"           (TList TInt)
    tcTest "let mut x = [1, 2]; x.insert(1, 9); x"     (TList TInt)
    tcTest "let mut x = [1, 2]; x.remove(0); x"        (TList TInt)

  describe "TypeChecker Phase 2A: list type errors" $ do
    tcErrorTest "let x = [1, 2]; x[true]"
    tcMsgTest   "let x = [1, 2]; x[true]"  "int"
    tcErrorTest "let mut x = [1, 2]; x.push(true); x"
    tcMsgTest   "let mut x = [1, 2]; x.push(true); x"  "bool"
    tcErrorTest "let x = [1, true]"
    tcErrorTest "let x = Red; x[0]"
    tcMsgTest   "let x = Red; x[0]"  "index"

  describe "TypeChecker Phase 2A: lists are move types" $ do
    tcErrorTest "let x = [1, 2]; let y = x; x"
    tcMsgTest   "let x = [1, 2]; let y = x; x"  "moved"

  describe "TypeChecker Phase 2A: list mutation rejected while borrowed" $ do
    tcErrorTest "let mut xs = [1, 2, 3]; let r = &xs; xs.push(4); *r"
    tcMsgTest   "let mut xs = [1, 2, 3]; let r = &xs; xs.push(4); *r"    "borrowed"
    tcErrorTest "let mut xs = [1, 2, 3]; let r = &xs; xs.remove(0); *r"
    tcErrorTest "let mut xs = [1, 2, 3]; let r = &xs; xs.insert(0, 9); *r"
    tcErrorTest "let mut xs = [1, 2, 3]; let r = &xs; xs[0] = 9; *r"
    tcTest      "let mut xs = [1, 2]; xs.push(3); xs" (TList TInt)

  describe "TypeChecker Phase 2B: int is Copy (can be read any number of times)" $ do
    tcTest "let x = 5; let y = x; x + y"                   TInt
    tcTest "let x = 5; let y = x; let z = x; x + y + z"   TInt
    tcTest "fn f(a: int) -> int { a }; let x = 3; f(x); f(x); x" TInt

  describe "TypeChecker Phase 2B: bool is Copy (can be read any number of times)" $ do
    tcTest "let b = true; let c = b; b && c"              TBool
    tcTest "let b = true; let c = b; let d = b; b && c && d" TBool
    tcTest "fn g(a: bool) -> bool { a }; let b = true; g(b); g(b); b" TBool

  describe "TypeChecker Phase 2B: Light and lists remain non-Copy" $ do
    tcErrorTest "let x = Red; let y = x; x"
    tcMsgTest   "let x = Red; let y = x; x"   "moved"
    tcErrorTest "let x = [1, 2]; let y = x; x"
    tcMsgTest   "let x = [1, 2]; let y = x; x" "moved"

  describe "TypeChecker Phase 2C: Result construction" $ do
    tcTest "Ok(5)"           (TResult TInt)
    tcTest "Err(0)"          (TResult TInt)
    tcTest "Ok(true)"        (TResult TBool)
    tcTest "let r = Ok(42); r" (TResult TInt)

  describe "TypeChecker Phase 2C: pair construction and type" $ do
    tcTest "(1, 2)"          (TPair TInt TInt)
    tcTest "(5, true)"       (TPair TInt TBool)
    tcTest "(Red, 0)"        (TPair TLight TInt)

  describe "TypeChecker Phase 2C: match on Light" $ do
    tcTest "match Red { Red => 1, Yellow => 2, Green => 3 }"                     TInt
    tcTest "match Green { Red => true, Yellow => false, Green => true }"         TBool
    tcTest "let x = Red; match x { Red => 1, Yellow => 2, Green => 3 }"         TInt

  describe "TypeChecker Phase 2C: match on Result" $ do
    tcTest "let r = Ok(5); match r { Ok(v) => v, Err(e) => 0 }"         TInt
    tcTest "let r = Err(1); match r { Ok(v) => v + 1, Err(e) => e }"    TInt
    tcTest "fn use_r(r: Result<int>) -> int { match r { Ok(v) => v, Err(e) => e } }; use_r(Ok(7))" TInt

  describe "TypeChecker Phase 2C: match on pair" $ do
    tcTest "let p = (3, 4); match p { (x, y) => x + y }"                TInt
    tcTest "let p = (1, true); match p { (n, b) => n }"                 TInt

  describe "TypeChecker Phase 2C: wildcard pattern" $ do
    tcTest "match Red { r => 0 }"                                        TInt
    tcTest "let p = (1, 2); match p { w => 0 }"                         TInt

  describe "TypeChecker Phase 2C: non-exhaustive match is rejected" $ do
    tcErrorTest "match Red { Red => 1, Yellow => 2 }"
    tcMsgTest   "match Red { Red => 1, Yellow => 2 }"   "exhaustive"
    tcErrorTest "match Ok(5) { Ok(v) => v }"
    tcMsgTest   "match Ok(5) { Ok(v) => v }"   "exhaustive"

  describe "TypeChecker Phase 2C: match type errors" $ do
    tcErrorTest "match 5 { Red => 1, Yellow => 2, Green => 3 }"
    tcMsgTest   "match 5 { Red => 1, Yellow => 2, Green => 3 }"  "Cannot match"
    tcErrorTest "match Red { Red => 1, Yellow => 2, Green => true }"
    tcMsgTest   "match Red { Red => 1, Yellow => 2, Green => true }" "expected"

  describe "TypeChecker Phase 2C: Result is non-Copy when inner type is non-Copy" $ do
    tcErrorTest "let r = Ok(Red); let s = r; r"
    tcMsgTest   "let r = Ok(Red); let s = r; r"  "moved"

  describe "TypeChecker Phase 2C: pair is Copy when both components are Copy" $ do
    tcTest "let p = (1, true); let q = p; p"  (TPair TInt TBool)

  describe "TypeChecker Phase 3A: borrow creation and dereference" $ do
    tcTest "let x = 5; let r = &x; *r"                        TInt
    tcTest "let x = true; let r = &x; *r"                     TBool
    tcTest "let x = Red; let r = &x; *r"                      TLight
    tcTest "let x = 5; let r = &x; *r + 1"                    TInt

  describe "TypeChecker Phase 3A: borrow does not prevent later reads" $ do
    tcTest "let x = 5; let r = &x; x + *r"                    TInt
    tcTest "let x = 5; let r = &x; *r + x"                    TInt

  describe "TypeChecker Phase 3A: borrow that's still live prevents move of non-Copy value" $ do
    tcErrorTest "let x = Red; let r = &x; let v = x; *r"
    tcMsgTest   "let x = Red; let r = &x; let v = x; *r"      "borrowed"
    tcErrorTest "let x = [1, 2]; let r = &x; let v = x; *r"
    tcMsgTest   "let x = [1, 2]; let r = &x; let v = x; *r"   "borrowed"

  describe "TypeChecker Phase 3A: borrow expires when reference leaves scope" $ do
    tcTest "let x = Red; { let r = &x }; x"                   TLight
    tcTest "let x = [1, 2]; { let r = &x }; x"                (TList TInt)

  describe "TypeChecker Phase 3A: functions taking reference parameters" $ do
    tcTest "fn deref_int(r: &int) -> int { *r }; let x = 5; deref_int(&x)" TInt
    tcTest "fn f(r: &int) -> int { *r }; let x = 5; f(&x); x"              TInt

  describe "TypeChecker Phase 3A: cannot return a reference from a function" $ do
    tcErrorTest "fn bad(x: int) -> &int { &x }; 0"
    tcMsgTest   "fn bad(x: int) -> &int { &x }; 0"            "reference"

  describe "TypeChecker Phase 3A: use-after-free detected (borrow would dangle)" $ do
    tcErrorTest "let y = Red; let mut r = &y; { let x = Red; r = &x }; *r"
    tcMsgTest   "let y = Red; let mut r = &y; { let x = Red; r = &x }; *r" "dropped while still borrowed"

  describe "TypeChecker Phase 3A: deref type error" $ do
    tcErrorTest "let x = 5; *x"
    tcMsgTest   "let x = 5; *x"                                "Cannot dereference"

  describe "TypeChecker Phase 3B: basic mutable borrow creation and dereference" $ do
    tcTest "let mut x = 5; let b = &mut x; *b"                TInt
    tcTest "let mut x = true; let b = &mut x; *b"             TBool
    tcTest "let mut x = Red; let b = &mut x; *b"              TLight

  describe "TypeChecker Phase 3B: mutable borrow of immutable variable is rejected" $ do
    tcErrorTest "let x = 5; let b = &mut x; *b"
    tcMsgTest   "let x = 5; let b = &mut x; *b"               "not mutable"

  describe "TypeChecker Phase 3B: exclusivity - no two mutable borrows" $ do
    tcErrorTest "let mut x = 5; let b1 = &mut x; let b2 = &mut x; *b1"
    tcMsgTest   "let mut x = 5; let b1 = &mut x; let b2 = &mut x; *b1" "already mutably borrowed"

  describe "TypeChecker Phase 3B: exclusivity - mutable borrow blocks immutable (both used)" $ do
    tcErrorTest "let mut x = 5; let b = &mut x; let r = &x; *r + *b"
    tcMsgTest   "let mut x = 5; let b = &mut x; let r = &x; *r + *b" "already mutably borrowed"

  describe "TypeChecker Phase 3B: exclusivity - immutable borrow blocks mutable (both used)" $ do
    tcErrorTest "let mut x = 5; let r = &x; let b = &mut x; *r + *b"
    tcMsgTest   "let mut x = 5; let r = &x; let b = &mut x; *r + *b" "already borrowed"

  describe "TypeChecker Phase 3B: mutable borrow that's still live prevents move of non-Copy value" $ do
    tcErrorTest "let mut x = Red; let b = &mut x; let v = x; *b"
    tcMsgTest   "let mut x = Red; let b = &mut x; let v = x; *b" "borrowed"

  describe "TypeChecker Phase 3B: mutable borrow expires when ref leaves scope" $ do
    tcTest "let mut x = Red; { let b = &mut x }; x"           TLight
    tcTest "let mut x = 5; { let b = &mut x }; x"             TInt

  describe "TypeChecker Phase 3B: SDerefAssign writes through mutable ref" $ do
    tcTest "let mut x = 5; let b = &mut x; *b = 10; *b"       TInt
    tcTest "let mut x = Red; let b = &mut x; *b = Green; *b"  TLight

  describe "TypeChecker Phase 3B: SDerefAssign through immutable ref is rejected" $ do
    tcErrorTest "let x = 5; let r = &x; *r = 10; *r"
    tcMsgTest   "let x = 5; let r = &x; *r = 10; *r"          "immutable reference"

  describe "TypeChecker Phase 3B: place-expression allows double deref of &mut" $ do
    tcTest "fn f(b: &mut int) -> int { *b + *b }; let mut x = 21; f(&mut x)" TInt

  describe "TypeChecker Phase 3B: cannot return mutable reference from function" $ do
    tcErrorTest "fn bad(mut x: int) -> &mut int { &mut x }; 0"
    tcMsgTest   "fn bad(mut x: int) -> &mut int { &mut x }; 0" "reference"

  describe "TypeChecker Phase 3B: set_red spec example" $ do
    tcTest "fn set_red(mut light: &mut Light) -> () { *light = Red }; let mut l = Green; set_red(&mut l); l"
           TLight

  describe "TypeChecker Phase 3B: ERefMut in function arg rejected while immutable borrow still live" $ do
    tcErrorTest "fn change(x: &mut int) -> () { *x = 5 }; let mut x = 1; let r = &x; change(&mut x); *r"
    tcMsgTest   "fn change(x: &mut int) -> () { *x = 5 }; let mut x = 1; let r = &x; change(&mut x); *r"
                "already borrowed"

  describe "TypeChecker Phase 3B: ERef in function arg rejected while mutable borrow still live" $ do
    tcErrorTest "fn read(x: &int) -> int { *x }; let mut x = 1; let b = &mut x; read(&x); *b"
    tcMsgTest   "fn read(x: &int) -> int { *x }; let mut x = 1; let b = &mut x; read(&x); *b"
                "already mutably borrowed"

  describe "TypeChecker Phase 3B: ERefMut in function arg allowed when no borrow active" $ do
    tcTest "fn change(x: &mut int) -> () { *x = 5 }; let mut x = 1; change(&mut x); 0" TInt

  describe "TypeChecker Phase 3B: ERefMut in function arg allowed after NLL releases prior borrow" $ do
    tcTest "fn change(x: &mut int) -> () { *x = 5 }; let mut x = 1; let r = &x; let dummy = *r; change(&mut x); 0" TInt

  describe "TypeChecker Phase 3B: copying immutable ref propagates borrow - move of referent rejected" $ do
    tcErrorTest "let x = Red; let r = &x; let s = r; let y = x; *s"
    tcMsgTest   "let x = Red; let r = &x; let s = r; let y = x; *s" "borrowed"

  describe "TypeChecker Phase 3B: copying immutable ref - both copies keep referent borrowed" $ do
    tcErrorTest "let mut x = Red; let r = &x; let s = r; x = Green; *s"
    tcMsgTest   "let mut x = Red; let r = &x; let s = r; x = Green; *s" "borrowed"

  describe "TypeChecker Phase 3B: copying immutable ref - NLL expires both copies, then move allowed" $ do
    tcTest "let x = Red; let r = &x; let s = r; let dummy = *s; x" TLight

  describe "TypeChecker Phase 3B: moving mutable ref propagates borrow - move of non-Copy referent blocked" $ do
    tcErrorTest "let mut x = Red; let b = &mut x; let c = b; let y = x; *c"
    tcMsgTest   "let mut x = Red; let b = &mut x; let c = b; let y = x; *c" "borrowed"

  describe "TypeChecker Phase 3B: moving mutable ref - original ref is consumed" $ do
    tcErrorTest "let mut x = 5; let b = &mut x; let c = b; *b"
    tcMsgTest   "let mut x = 5; let b = &mut x; let c = b; *b" "used after being moved"

  describe "TypeChecker Phase 3B: assigning immutable ref copy via s = r propagates borrow" $ do
    tcErrorTest "let x = Red; let r = &x; let mut s = &x; s = r; let y = x; *s"
    tcMsgTest   "let x = Red; let r = &x; let mut s = &x; s = r; let y = x; *s" "borrowed"

  describe "TypeChecker Phase 3C: NLL - unused borrow expires immediately" $ do
    tcTest "let x = Red; let r = &x; x"                        TLight
    tcTest "let x = [1, 2]; let r = &x; x"                    (TList TInt)
    tcTest "let mut x = Red; let b = &mut x; x"                TLight

  describe "TypeChecker Phase 3C: NLL - borrow expires at last use, not scope end" $ do
    tcTest "let mut x = 5; let r = &x; *r; x = 10; x"         TInt
    tcTest "let mut x = Red; let r = &x; *r; x = Green; x"    TLight

  describe "TypeChecker Phase 3C: NLL - mutable borrow expires at last use" $ do
    tcTest "let mut x = 5; let b = &mut x; *b; x = 20; x"     TInt

  describe "TypeChecker Phase 3C: NLL - borrow in inner block expires early" $ do
    tcTest "let mut x = 5; { let r = &x; *r }; x = 10; x"     TInt

  describe "TypeChecker Phase 4A: lifetime-generic functions can return references" $ do
    tcTest "fn id_ref<'a>(x: &'a int) -> &'a int { x }; let y = 5; let r = id_ref(&y); *r"
           TInt
    tcTest "fn id_ref<'a>(x: &'a Light) -> &'a Light { x }; let c = Red; let r = id_ref(&c); *r"
           TLight
    tcTest "fn first<'a, 'b>(x: &'a int, y: &'b int) -> &'a int { x }; let a = 3; let b = 4; let r = first(&a, &b); *r"
           TInt

  describe "TypeChecker Phase 4A: lifetime function used for dereference only" $ do
    tcTest "fn deref_lt<'a>(x: &'a int) -> int { *x }; let y = 42; deref_lt(&y)"    TInt
    tcTest "fn id_ref<'a>(x: &'a int) -> &'a int { x }; let y = 5; let r = id_ref(&y); *r + y"  TInt

  describe "TypeChecker Phase 4A: non-lifetime function still cannot return reference" $ do
    tcErrorTest "fn bad(x: &int) -> &int { x }; 0"
    tcMsgTest   "fn bad(x: &int) -> &int { x }; 0"                "reference"

  describe "TypeChecker Phase 4A: undeclared lifetime in return type is rejected" $ do
    tcErrorTest "fn bad<'a>(x: &'a int) -> &'b int { x }; 0"
    tcMsgTest   "fn bad<'a>(x: &'a int) -> &'b int { x }; 0"      "undeclared lifetime"

  describe "TypeChecker Phase 4A: undeclared lifetime in parameter type is rejected" $ do
    tcErrorTest "fn bad<'a>(x: &'b int) -> int { *x }; 0"
    tcMsgTest   "fn bad<'a>(x: &'b int) -> int { *x }; 0"         "undeclared lifetime"
    tcErrorTest "fn bad<'a>(x: &'a int, y: &'b int) -> int { *x }; 0"
    tcTest      "fn good<'a>(x: &'a int) -> int { *x }; let v = 5; let r = &v; good(r)" TInt

  describe "TypeChecker Phase 4A: returned reference preserves borrow" $ do
    tcErrorTest "fn id_ref<'a>(x: &'a Light) -> &'a Light { x }; let c = Red; let r = id_ref(&c); let v = c; *r"
    tcMsgTest   "fn id_ref<'a>(x: &'a Light) -> &'a Light { x }; let c = Red; let r = id_ref(&c); let v = c; *r"
                "borrowed"

  describe "TypeChecker Phase 4B: spawn - well-typed programs" $ do
    tcTest "spawn { }; 42"                                      TInt
    tcTest "let x = 5; spawn { let y = x }; x"                 TInt
    tcTest "let b = true; spawn { let c = b }; b"              TBool
    tcTest "spawn { let mut n = 0; n = n + 1 }; 0"             TInt

  describe "TypeChecker Phase 4B: spawn - non-Copy captures rejected" $ do
    tcErrorTest "let x = Red; spawn { let y = x }; 0"
    tcMsgTest   "let x = Red; spawn { let y = x }; 0"          "non-Copy"
    tcErrorTest "let x = [1, 2]; spawn { let y = x }; 0"
    tcMsgTest   "let x = [1, 2]; spawn { let y = x }; 0"       "non-Copy"

  describe "TypeChecker Phase 4B: spawn - mutable reference (not Copy) rejected" $ do
    tcErrorTest "let mut x = 5; let b = &mut x; spawn { *b }; x"
    tcMsgTest   "let mut x = 5; let b = &mut x; spawn { *b }; x" "non-Copy"

  describe "TypeChecker Phase 4B: spawn - immutable reference (Copy) is allowed" $ do
    tcTest "let x = 5; let r = &x; spawn { let y = *r }; *r"  TInt

  describe "TypeChecker Phase 0: if-else branches checked independently (issue #4)" $ do
    tcTest "fn consume(x: Light) -> () {}; let x = Red; if true { consume(x) } else { consume(x) }; 0" TInt
    tcTest "fn consume(x: Light) -> () {}; let x = Red; let y = Green; if true { consume(x) } else { consume(y) }; 0" TInt
    tcErrorTest "fn consume(x: Light) -> () {}; let x = Red; if true { consume(x) } else { 0 }; x"
    tcErrorTest "fn consume(x: Light) -> () {}; let x = Red; if true { consume(x) } else { consume(x) }; x"

  describe "TypeChecker Phase 0: while loop may not move outer non-Copy variables (issue #5)" $ do
    tcErrorTest "fn consume(x: Light) -> () {}; let x = Red; let mut i = 0; while i < 2 { consume(x); i = i + 1 }; 0"
    tcMsgTest   "fn consume(x: Light) -> () {}; let x = Red; let mut i = 0; while i < 2 { consume(x); i = i + 1 }; 0" "while loop"
    tcTest "let mut x = 0; while x < 5 { x = x + 1 }; x" TInt
    tcTest "fn consume(x: Light) -> () {}; let mut i = 0; while i < 2 { let y = Red; consume(y); i = i + 1 }; 0" TInt
