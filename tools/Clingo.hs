module Clingo where

import System.IO
import System.Process
import Control.Monad
import Control.Applicative
import Data.Maybe
import Data.List
import Data.Char

type Parse a = String -> Maybe (a, String)

newtype Name = Name String deriving (Eq, Show)
data Fact = Fact Name [Term] deriving Show
data Term = TInt Integer | TStr String | TFun Name [Term] deriving Show

-- ASP code passed to runClingo.
data ClingoInput
   = CICode String
   | CIFile FilePath
   deriving Show

-- Return value of runClingo.
data ClingoResult
   = CRSatisfiable [Answer]
   | CRUnsatisfiable
   deriving Show

type Answer = [Fact]

-- Options passed to runClingo.
data RunClingoOptions = RunClingoOptions{
    rcClingoArgs :: [String], -- Additional arguments to be passed to Clingo.
    rcEchoStdout :: Bool,     -- If True, Clingo's stdout is copied to stdout.
    rcEchoInput  :: Bool }    -- If True, the input ASP is copied to stdout.

-- RunClingoOptions with default values.
runClingoOptions = RunClingoOptions{
    rcClingoArgs = [],
    rcEchoStdout = True,
    rcEchoInput  = False }

--------------------------------------------------------------------------------
-- Run Clingo 3, which is assumed to be present on the search path as 'clingo',
-- with the given input strings/files, and with the given arguments appended.
-- Returns either CRSatisfiable [answer1, answer2, ...], where the answerN are
-- given in reverse order, or CRUnsatisfiable. In particular, if an optimum
-- is reported by Clingo, this is given as the first answer in the list.
runClingo :: RunClingoOptions -> [ClingoInput] -> IO ClingoResult
runClingo options inputs = do
    let args = "-" : extraArgs
    let spec = (proc "clingo" args) { std_in=CreatePipe, std_out=CreatePipe }
    (Just clingoIn, Just clingoOut, _, clingoProc) <- createProcess spec
    forM inputs $ \input -> do
        code <- case input of
            CICode code -> return code
            CIFile path -> readFile path
        when (echoInput) $ forM_ (lines code) $ \line -> do
            putStrLn $ "<-- " ++ line
        hPutStr clingoIn code
    hClose clingoIn
    result <- readClingo [] clingoOut
    waitForProcess clingoProc
    return result
  where
    RunClingoOptions{
        rcClingoArgs = extraArgs,
        rcEchoStdout = echoStdout,
        rcEchoInput  = echoInput } = options
    readClingo :: [[Fact]] -> Handle -> IO ClingoResult
    readClingo answers clingoOut = do
        line <- ehGetLine clingoOut
        case line of
            _ | "Answer: " `isPrefixOf` line -> do
                line <- ehGetLine clingoOut
                let Just (answer, "") = readFacts line
                readClingo (answer : answers) clingoOut
            "SATISFIABLE" ->
                return (CRSatisfiable answers)
            "OPTIMUM FOUND" ->
                return (CRSatisfiable answers)
            "UNSATISFIABLE" ->
                return CRUnsatisfiable
            _ ->
                readClingo answers clingoOut
    ehGetLine :: Handle -> IO String
    ehGetLine handle = do
        line <- hGetLine handle
        when echoStdout $ putStrLn $ "--> " ++ line
        return line

--------------------------------------------------------------------------------
-- Read a space-separated list of facts.
readFacts :: Parse [Fact]
readFacts "" = do
    return ([], "")
readFacts str = do
    (fact, str) <- readFact str
    (_,str) <- return (span isSpace str)
    (facts, str) <- readFacts str <|> return ([], str)
    return (fact:facts, str)

showFacts :: [Fact] -> String
showFacts facts = concat (intersperse " " (map showFact facts))

showFactLines :: [Fact] -> [String]
showFactLines facts = map ((++ ".") . showFact) facts

--------------------------------------------------------------------------------
-- Read a fact: a predicate symbol with 0 or more term arguments.
readFact :: Parse Fact
readFact = readSymbol Fact

showFact :: Fact -> String
showFact (Fact name args) = showSymbol name args

--------------------------------------------------------------------------------
-- Read a term: an integer, string, name, or function symbol with arguments.
readTerm :: Parse Term
readTerm str
  = readValue TInt str <|> readValue TStr str <|> readSymbol TFun str

showTerm term = case term of
    TInt int       -> show int
    TStr str       -> show str
    TFun name args -> showSymbol name args

--------------------------------------------------------------------------------
readSymbol :: (Name -> [Term] -> a) -> Parse a
readSymbol con str = do
    (name, str) <- readName str
    (args, str) <- readArgs str <|> return ([], str)
    return (con name args, str)

showSymbol :: Name -> [Term] -> String
showSymbol (Name name) args = name ++ showArgs args

--------------------------------------------------------------------------------
readValue :: Read a => (a -> b) -> Parse b
readValue con str = do
    (value, str) <- listToMaybe (reads str)
    return (con value, str)

--------------------------------------------------------------------------------
readName :: Parse Name
readName str = do
    guard (any isLower $ take 1 str)
    let (name, rest) = span (\c -> isAlphaNum c || c == '_') str
    return (Name name, rest)

--------------------------------------------------------------------------------
readArgs :: Parse [Term]
readArgs str = do
    '(':str <- return str
    (_,str) <- return (span isSpace str)
    (arg, str) <- readTerm str
    (args, str) <- readArgs' str <|> return ([], str)
    (_,str) <- return (span isSpace str)
    ')':str <- return str
    return (arg:args, str)

readArgs' :: Parse [Term]
readArgs' str = do
    (_,str) <- return (span isSpace str)
    ',':str <- return str
    (_,str) <- return (span isSpace str)
    (arg, str) <- readTerm str
    (args, str) <- readArgs' str <|> return ([], str)
    return (arg:args, str)

showArgs :: [Term] -> String
showArgs []   = ""
showArgs args = "(" ++ concat (intersperse "," (map showTerm args)) ++ ")"
