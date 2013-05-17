{-# LANGUAGE TypeFamilies, FlexibleContexts, ScopedTypeVariables #-}
-- | This module is designed to be imported qualified:
--
-- >import qualified Distribution.HaskellSuite.Compiler as Compiler
module Distribution.HaskellSuite.Compiler
  (
  -- * Compiler description
    Is(..)
  , CompileFn

  -- * Simple compiler
  , Simple
  , simple

  -- * Command line
  -- | Compiler's entry point.
  --
  -- It parses command line options (that are typically passed by Cabal) and
  -- invokes the appropriate compiler's methods.
  , main
  )
  where

import Data.Version
import Distribution.HaskellSuite.Packages
import {-# SOURCE #-} Distribution.HaskellSuite.Cabal
import Distribution.Simple.Compiler
import Distribution.Simple.Utils
import Distribution.Verbosity
import Distribution.InstalledPackageInfo
import Distribution.Package
import Distribution.ModuleName (ModuleName)
import Control.Monad
import Control.Exception
import Data.Maybe
import Data.List
import Language.Haskell.Exts.Annotated.CPP
import Language.Haskell.Exts.Extension

-- | Compilation function
type CompileFn = FilePath -> [Extension] -> CpphsOptions -> PackageDBStack -> [InstalledPackageId] -> [FilePath] -> IO ()

-- | An abstraction over a Haskell compiler.
--
-- Once you've written a @Compiler.@'Is' instance, you get Cabal
-- integration for free (via @Compiler@.'main').
--
-- Consider whether @Compiler.@'Simple' suits your needs — then you need to
-- write even less code.
--
-- Minimal definition: 'DB', 'name', 'version', 'fileExtensions',
-- 'compile', 'languageExtensions'.
--
-- 'fileExtensions' are only used for 'installLib', so if you define
-- a custom 'installLib', 'fileExtensions' won't be used (but you'll still
-- get a compiler warning if you do not define it).
class IsPackageDB (DB compiler) => Is compiler where

  -- | The database type used by the compiler
  type DB compiler

  -- | Compiler's name
  name :: compiler -> String
  -- | Compiler's version
  version :: compiler -> Version
  -- | File extensions of the files generated by the compiler. Those files
  -- will be copied during the install phase.
  fileExtensions :: compiler -> [String]
  -- | How to compile a set of modules
  compile :: compiler -> CompileFn
  -- | Extensions supported by this compiler
  languageExtensions :: compiler -> [Extension]

  installLib
      :: compiler
      -> FilePath -- ^ build dir
      -> FilePath -- ^ target dir
      -> Maybe FilePath -- ^ target dir for dynamic libraries
      -> PackageIdentifier
      -> [ModuleName]
      -> IO ()
  installLib t buildDir targetDir _dynlibTargetDir _pkg mods =
    findModuleFiles [buildDir] (fileExtensions t) mods
      >>= installOrdinaryFiles normal targetDir

  -- | Register the package in the database
  register
    :: compiler
    -> PackageDB
    -> InstalledPackageInfo
    -> IO ()
  register t dbspec pkg = do
    mbDb <- locateDB dbspec

    case mbDb :: Maybe (DB compiler) of
      Nothing -> throwIO RegisterNullDB
      Just db -> do
        pkgs <- readPackageDB InitDB db
        let pkgid = installedPackageId pkg
        when (isJust $ findPackage pkgid pkgs) $
          throwIO $ PkgExists pkgid
        writePackageDB db $ pkg:pkgs

findPackage :: InstalledPackageId -> Packages -> Maybe InstalledPackageInfo
findPackage pkgid = find ((pkgid ==) . installedPackageId)

data Simple db = Simple
  { stName :: String
  , stVer :: Version
  , stLangExts :: [Extension]
  , stCompile :: CompileFn
  , stExts :: [String]
  }

simple
  :: String -- ^ compiler name
  -> Version -- ^ compiler version
  -> [Extension]
  -> CompileFn
  -> [String] -- ^ extensions that generated file have
  -> Simple db
simple = Simple

instance IsPackageDB db => Is (Simple db) where
  type DB (Simple db) = db

  name = stName
  version = stVer
  fileExtensions = stExts
  compile = stCompile
  languageExtensions = stLangExts
