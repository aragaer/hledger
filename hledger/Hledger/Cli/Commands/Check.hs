{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TemplateHaskell #-}

module Hledger.Cli.Commands.Check (
  checkmode
 ,check
) where

import Hledger
import Hledger.Cli.CliOptions
import Hledger.Cli.Commands.Checkdupes (checkdupes)
import Hledger.Cli.Commands.Checkdates (checkdates)
import System.Console.CmdArgs.Explicit
import Data.Either (partitionEithers)
import Data.Char (toUpper)
import Safe (readMay)
import Control.Monad (forM_)

checkmode :: Mode RawOpts
checkmode = hledgerCommandMode
  $(embedFileRelative "Hledger/Cli/Commands/Check.txt")
  []
  [generalflagsgroup1]
  hiddenflags
  ([], Just $ argsFlag "[CHECKS]")

check :: CliOpts -> Journal -> IO ()
check copts@CliOpts{rawopts_} j = do
  let 
    args = listofstringopt "args" rawopts_
    -- reset the report spec that was generated by argsToCliOpts,
    -- since we are not using arguments as a query in the usual way
    copts' = cliOptsUpdateReportSpecWith (\ropts -> ropts{querystring_=[]}) copts

  case partitionEithers (map parseCheckArgument args) of
    (unknowns@(_:_), _) -> error' $ "These checks are unknown: "++unwords unknowns
    ([], checks) -> forM_ checks $ runCheck copts' j
      
-- | A type of error check that we can perform on the data.
data Check =
    Ordereddates
  | Uniqueleafnames
  deriving (Read,Show,Eq)

-- | Parse the name of an error check, or return the name unparsed.
-- Names are conventionally all lower case, but this parses case insensitively.
parseCheck :: String -> Either String Check
parseCheck s = maybe (Left s) Right $ readMay $ capitalise s

capitalise :: String -> String
capitalise (c:cs) = toUpper c : cs
capitalise s = s

-- | Parse a check argument: a string which is the lower-case name of an error check,
-- followed by zero or more space-separated arguments for that check.
parseCheckArgument :: String -> Either String (Check,[String])
parseCheckArgument s =
  dbg3 "check argument" $
  ((,checkargs)) <$> parseCheck checkname
  where
    (checkname:checkargs) = words' s

-- | Run the named error check, possibly with some arguments, 
-- on this journal with these options.
runCheck :: CliOpts -> Journal -> (Check,[String]) -> IO ()
runCheck copts@CliOpts{rawopts_} j (check,args) = 
  case check of
    Ordereddates     -> checkdates copts' j
    Uniqueleafnames -> checkdupes copts' j
  where
    -- Hack: append the provided args to the raw opts,
    -- in case the check can use them (like checkdates --unique). 
    -- Does not bother to regenerate the derived data (ReportOpts, ReportSpec..), 
    -- so those may be inconsistent.
    copts' = copts{rawopts_=appendopts (map (,"") args) rawopts_}

-- | Regenerate this CliOpts' report specification, after updating its
-- underlying report options with the given update function.
-- This can raise an error if there is a problem eg due to missing or
-- unparseable options data. See also updateReportSpecFromOpts.
cliOptsUpdateReportSpecWith :: (ReportOpts -> ReportOpts) -> CliOpts -> CliOpts
cliOptsUpdateReportSpecWith roptsupdate copts@CliOpts{reportspec_} =
  case updateReportSpecWith roptsupdate reportspec_ of
    Left e   -> error' e  -- PARTIAL:
    Right rs -> copts{reportspec_=rs}
