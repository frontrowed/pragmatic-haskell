module Main where

import Entities
import Control.Monad.IO.Class  (liftIO)
import Database.Persist
import Database.Persist.Sqlite
import Text.Megaparsec
import FooParser (parseSections, Section(..))
import qualified Database.Esqueleto as E
import Control.Monad
import Database.Persist.Sql (toSqlKey)

main :: IO ()
main = do
  fileContents <- readFile "specs.foo"

  -- parse specs.foo
  let sections = case runParser parseSections "specs.foo" fileContents of
        Left err        -> error $ "could not parse .foo file with error: " ++ show err
        Right sections' -> sections'
        :: [Section]

  -- run everything inside single connection/txn against a sqlite file
  runSqlite "ourdb.sqlite" $ do

    runMigration migrateAll

    -- insert user and pagaraph in one go
    forM_ sections $ \section -> do
      let user = User { userName = sectionUsername section }
      userId <- insert user
      forM_ (sectionParagraphs section) $ \p -> do
        let paragraph = Paragraph { paragraphContent = (unwords p)
                                  , paragraphUserId = userId
                                  }
        insert paragraph

    -- fetch all users (note GHC type hint here)
    userEntities <- selectList [] []
    liftIO $ do
      putStrLn ""
      putStrLn "Users:"
      print (userEntities :: [Entity User])

    allParags <- selectList ([] :: [Filter Paragraph]) []
    liftIO $ do
      putStrLn ""
      putStrLn "All Paragraphs:"
      print allParags

    -- let's fetch all users with filter, (questionably useful) limit and
    -- ordering
    userEntities' <- selectList [UserName ==. "alex"] [LimitTo 1, Asc UserName]
    liftIO $ do
      putStrLn ""
      putStrLn "Users:"
      print userEntities'

    allParags <- selectList ([] :: [Filter Paragraph]) []
    liftIO $ do
      putStrLn ""
      putStrLn "All Paragraphs:"
      print allParags

    -- sample update
    _ <- updateWhere [ParagraphId ==. (toSqlKey 1)] [ParagraphContent =. "foo"]

    -- sample delete
    _ <- deleteWhere [ParagraphContent ==. "foo"]

    -- uh oh.. how do I join? could do raw sql as a last resort
    let sql = "SELECT ?? \
             \ FROM users \
             \ INNER JOIN paragraphs ON users.id = paragraphs.user_id \
             \ WHERE users.name = ?"
    alexRawParags <- rawSql sql [PersistText "alex"]
    liftIO $ do
      putStrLn ""
      putStrLn "Alex's Raw Paragraphs:"
      -- GHC has no clue what the raw sql is returning unless I tell it
      print (alexRawParags :: [Entity Paragraph])

    -- eh, that works, but we can do much better. esqueleto to the rescue
    alexParags <- E.select $
                  E.from $ \(users `E.InnerJoin` paragraphs) -> do
                  E.on ((users E.^. UserId) E.==. (paragraphs E.^.ParagraphUserId))
                  E.where_ ((users E.^. UserName) E.==. (E.val "alex"))
                  return paragraphs

    liftIO $ do
      putStrLn ""
      putStrLn "Alex's Esqueleto Paragraphs:"
      print alexParags

    -- we can compose! Define fn giving us alex where clause
    let whereClause table = E.where_ ((table E.^. UserName) E.==. (E.val "alex"))

    alexFirstParag <- E.select $
                      E.from $ \(users `E.LeftOuterJoin` paragraphs) -> do
                      E.on ((users E.^. UserId) E.==. (paragraphs E.^.ParagraphUserId))
                      (whereClause users) -- can reuse this!
                      E.limit 1
                      E.orderBy [E.asc (paragraphs E.^. ParagraphId)]
                      return paragraphs

    liftIO $ do
      putStrLn ""
      putStrLn "Alex's First Paragraph:"
      print alexFirstParag

    liftIO $ do
      putStrLn ""
      putStrLn "--- all done ---"
