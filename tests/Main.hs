{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE NoImplicitPrelude #-}


module Main where


import BasePrelude
-- Trees
import qualified Data.Tree as Tree
-- Text
import qualified Data.Text as T
import Data.Text (Text)
-- Tests
import Test.Hspec
import Test.QuickCheck
import Test.Hspec.QuickCheck
-- Markdown
import CMark
import CMark.Sections


main :: IO ()
main = hspec $ do
  let mkSect level heading content ns =
        Tree.Node
          (Section level heading () content ())
          ns
  describe "converting:" $ do
    it "empty document" $ do
      let src = ""
          preface = mempty
          prefaceAnn = ()
          sections = []
      nodesToDocument (commonmarkToNodesWithSource [] src)
        `shouldBe` Document{..}
    it "spaces" $ do
      let src = "  \n\n  \n"
          preface = WithSource "  \n\n  \n" []
          prefaceAnn = ()
          sections = []
      nodesToDocument (commonmarkToNodesWithSource [] src)
        `shouldBe` Document{..}
    it "paragraph" $ do
      let src = "x"
          preface = WithSource "x" [
            Node (Just (PosInfo 1 1 1 1)) PARAGRAPH [text "x"] ]
          prefaceAnn = ()
          sections = []
      nodesToDocument (commonmarkToNodesWithSource [] src)
        `shouldBe` Document{..}
    it "3 paragraphs" $ do
      let src = T.unlines ["","x","","","y","","z",""]
          preface = WithSource "\nx\n\n\ny\n\nz\n\n" [
            Node (Just (PosInfo 2 1 2 1)) PARAGRAPH [text "x"],
            Node (Just (PosInfo 5 1 5 1)) PARAGRAPH [text "y"],
            Node (Just (PosInfo 7 1 7 1)) PARAGRAPH [text "z"] ]
          prefaceAnn = ()
          sections = []
      nodesToDocument (commonmarkToNodesWithSource [] src)
        `shouldBe` Document{..}
    it "headers" $ do
      let src = T.unlines ["# 1", "", "## 2", "", "## 3"]
          preface = mempty
          prefaceAnn = ()
          sections = [
            mkSect 1 (WithSource "# 1\n\n" [text "1"]) mempty [
              mkSect 2 (WithSource "## 2\n\n" [text "2"]) mempty [],
              mkSect 2 (WithSource "## 3\n" [text "3"]) mempty [] ] ]
      nodesToDocument (commonmarkToNodesWithSource [] src)
        `shouldBe` Document{..}
    it "headers+content" $ do
      let src = T.unlines ["# 1", "", "## 2", "test", "## 3"]
          preface = mempty
          prefaceAnn = ()
          sections = [
            mkSect 1 (WithSource "# 1\n\n" [text "1"]) mempty [
              mkSect 2 (WithSource "## 2\n" [text "2"])
                (WithSource "test\n" [Node (Just (PosInfo 4 1 4 4)) PARAGRAPH
                                      [text "test"]]) [],
              mkSect 2 (WithSource "## 3\n" [text "3"]) mempty [] ] ]
      nodesToDocument (commonmarkToNodesWithSource [] src)
        `shouldBe` Document{..}
    it "preface+headers" $ do
      let src = T.unlines ["blah", "# 1", "", "## 2", "", "## 3"]
          preface = commonmarkToNodesWithSource [] "blah\n"
          prefaceAnn = ()
          sections = [
            mkSect 1 (WithSource "# 1\n\n" [text "1"]) mempty [
              mkSect 2 (WithSource "## 2\n\n" [text "2"]) mempty [],
              mkSect 2 (WithSource "## 3\n" [text "3"]) mempty [] ] ]
      nodesToDocument (commonmarkToNodesWithSource [] src)
        `shouldBe` Document{..}

  describe "reconstruction:" $ do
    it "paragraph + ###-header" $
      fromToDoc "foo\n\n# bar\n"
    it "paragraph + ===-header" $
      fromToDoc "foo\n\nbar\n===\n"
    it "no blank line after header" $
      fromToDoc "# header\n# header\n"
    it "header + blockquote" $
      fromToDoc "# header\n\n> a blockquote\n"
    it "header + list" $
      fromToDoc "# header\n * item\n"
    it "blanks + header" $
      fromToDoc "\n\n\n# header\n"
    modifyMaxSize (*20) $ modifyMaxSuccess (*10) $
      prop "QuickCheck" $
        forAllShrink mdGen shrinkMD $ \(T.concat -> src) ->
          let md1 = commonmarkToNodesWithSource [] src
              md2 = flattenDocument . nodesToDocument $ md1
              err = printf "%s: %s /= %s" (show src) (show md1) (show md2)
          in  counterexample err (compareMD md1 md2)

text :: Text -> Node
text t = Node Nothing (TEXT t) []

fromToDoc :: Text -> Expectation
fromToDoc src =
  flattenDocument (nodesToDocument (commonmarkToNodesWithSource [] src))
    `shouldBeMD` commonmarkToNodesWithSource [] src

shouldBeMD :: WithSource [Node] -> WithSource [Node] -> Expectation
shouldBeMD x y = x `shouldSatisfy` (compareMD y)

-- | Check that pieces of Markdown are equivalent (modulo trailing newline
-- and position info).
compareMD :: WithSource [Node] -> WithSource [Node] -> Bool
compareMD x y =
  map (\(Node _ a b) -> Node Nothing a b) (stripSource x) ==
  map (\(Node _ a b) -> Node Nothing a b) (stripSource y)
  &&
  or [getSource x == getSource y,
      and [not (T.isSuffixOf "\n" (getSource x)),
           T.isSuffixOf "\n" (getSource y),
           getSource x == T.init (getSource y)],
      and [not (T.isSuffixOf "\n" (getSource y)),
           T.isSuffixOf "\n" (getSource x),
           getSource y == T.init (getSource x)] ]

-- | Try to shrink Markdown.
shrinkMD :: [Text] -> [[Text]]
shrinkMD = shrinkList shrinkNothing

-- | Generate random Markdown.
mdGen :: Gen [Text]
mdGen = do
  ls <- listOf $ elements [
    -- ###-headers
    "# header 1\n", "# header 1 #\n",
    "## header 2\n",
    "### header 3\n",
    "#### header 4\n",
    "##### header 5\n",
    "###### header 6\n",
    " # header 1\n",   "  # header 1\n",
    " ## header 2\n",  "  ## header 2\n",
    -- ===-headers
    "header 1\n======\n", "header 2\n------\n",
    "multiline\nheader 1\n======\n", "multiline\nheader 2\n------\n",
    -- blocks with headers inside
    "> # header\n", "* # header\n",
    -- lists
    "* item\n", " * item\n",
    "+ item 1\n+ item 2\n",
    -- links and link references
    "[link][link]\n",
    "[link]: http://google.com\n",
    "> [link]: http://google.com\n",
    -- blockquotes
    "> blockquote\n> 1\n", ">> blockquote\n>> 2\n",
    -- other blocks
    "  a *paragraph*\n",
    "*multiline*\nparagraph\n",
    "~~~\ncode block\n~~~\n", "    code\n",
    "---\n", "* * *\n", " * * * \n",
    -- other things
    "", " ", "    ", "\n", "\n\n",
    "`", "``", "```"]
  let randomNL = T.replicate <$> choose (0, 3) <*> pure "\n"
  concat <$> mapM (\x -> do nl <- randomNL; return [x, nl]) ls
