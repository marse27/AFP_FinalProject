-- Shared context-merge helpers
module TypeCheck.Merge (mergeVarInfo, mergeContexts) where

import qualified Data.Map.Strict as Map
import qualified ScopeStack as SS
import Context (TcCtx, VarInfo (..), tcVars, tcFuns, view, set)

-- Here we combine the information stored for the same variable after checking two branches.
-- The variable keeps ownership only when both branches keep it.
-- Borrow counts use the larger value, because a borrow active in either branch must be retained to avoid forgetting an active borrow.
-- The borrowed source is kept only when it is the same in both branches.
mergeVarInfo :: VarInfo -> VarInfo -> VarInfo
mergeVarInfo vi1 vi2 = VarInfo
  { varType       = varType vi1
  , varMut        = varMut vi1
  , varOwned      = varOwned vi1 && varOwned vi2
  , varBorrows    = max (varBorrows vi1) (varBorrows vi2)
  , varMutBorrows = max (varMutBorrows vi1) (varMutBorrows vi2)
  , varBorrowOf   = if varBorrowOf vi1 == varBorrowOf vi2
                    then varBorrowOf vi1
                    else Nothing
  }

-- Here we combine two type-checker contexts produced by two branches.
-- A variable is considered owned afterwards only if it is still owned after both branches.
-- For active borrows, we keep the larger count because a borrow active in either branch must be retained.
-- Function information from both contexts is combined.
mergeContexts :: TcCtx -> TcCtx -> TcCtx
mergeContexts ctx1 ctx2 =
  set tcVars (SS.mergeWith mergeVarInfo (view tcVars ctx1) (view tcVars ctx2))
  $ set tcFuns (Map.union (view tcFuns ctx1) (view tcFuns ctx2))
  $ ctx1
