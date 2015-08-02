{-# LANGUAGE TypeSynonymInstances, FlexibleInstances, ScopedTypeVariables, EmptyDataDecls #-}
module Graphics.GPipe.Internal.PrimitiveArray where

import Graphics.GPipe.Internal.Buffer
import Graphics.GPipe.Internal.Shader
import Data.Monoid
import Foreign.C.Types
import Data.IORef

data VertexArray t a = VertexArray  { vertexArrayLength :: Int, bArrBFunc:: BInput -> a }

data Instances

newVertexArray :: Buffer os a -> Render os f (VertexArray t a)
newVertexArray buffer = Render $ return $ VertexArray (bufElementCount buffer) $ bufBElement buffer

instance Functor (VertexArray t) where
    fmap f (VertexArray n g) = VertexArray n (f . g)

zipVertices :: (a -> b -> c) -> VertexArray t a -> VertexArray t b -> VertexArray t c 
zipVertices h (VertexArray n f) (VertexArray m g) = VertexArray (min n m) (\x -> h (f x) (g x))

takeVertices :: Int -> VertexArray t a -> VertexArray t a
takeVertices n (VertexArray m f) = VertexArray (min n m) f

dropVertices :: Int -> VertexArray () a -> VertexArray t a
dropVertices n (VertexArray m f) = VertexArray n' g
        where
            n' = max (m - n) 0
            g bIn = f $ bIn { bInSkipElems = bInSkipElems bIn + n'}

replicateEach :: Int -> VertexArray t a -> VertexArray Instances a
replicateEach n (VertexArray m f) = VertexArray (n*m) (\x -> f $ x {bInInstanceDiv = bInInstanceDiv x * n})

class BufferFormat a => IndexFormat a where
    indexToInt :: a -> HostFormat a -> Int
    glType :: a -> Int
    indexToInt = error "You cannot create your own instances of IndexFormat"
    glType = error "You cannot create your own instances of IndexFormat"
        
instance IndexFormat BWord32 where
    indexToInt _ = fromIntegral  
    glType _ = glINT
instance IndexFormat BWord16 where
    indexToInt _ = fromIntegral  
    glType _ = glSHORT
instance IndexFormat BWord8 where
    indexToInt _ = fromIntegral    
    glType _ = glBYTE
    
data IndexArray = IndexArray { iArrName :: IORef CUInt, indexArrayLength:: Int, offset:: Int, restart:: Maybe Int, indexType :: Int } 
newIndexArray :: forall os f a. IndexFormat a => Buffer os a -> Maybe (HostFormat a) -> Render os f IndexArray
newIndexArray buf r = let a = undefined :: a in Render $ return $ IndexArray (bufName buf) (bufElementCount buf) 0 (fmap (indexToInt a) r) (glType a) 
 
takeIndices :: Int -> IndexArray -> IndexArray
takeIndices n i = i { indexArrayLength = min n (indexArrayLength i) }

dropIndices :: Int -> IndexArray -> IndexArray
dropIndices n i = i { indexArrayLength = max (l - n) 0, offset = offset i + n } where l = indexArrayLength i
 
glINT :: Int
glINT = undefined
glSHORT :: Int
glSHORT = undefined
glBYTE :: Int
glBYTE = undefined

class PrimitiveTopology p where
    toGLtopology :: p -> CUInt
    toGLtopology = error "You cannot create your own instances of IndexFormat"
    --data Geometry p :: * -> *
    --makeGeometry :: [a] -> Geometry p a  
   
data Triangles = TriangleStrip | TriangleList
data Lines = LineStrip | LineList
data Points = PointList
--data TrianglesWithAdjacency = TriangleStripWithAdjacency
--data LinesWithAdjacency = LinesWithAdjacencyList | LinesWithAdjacencyStrip   

instance PrimitiveTopology Triangles where
    toGLtopology TriangleStrip = 0
    toGLtopology TriangleList = 1
    --data Geometry Triangles a = Triangle a a a
   
instance PrimitiveTopology Lines where
    toGLtopology LineStrip = 0
    toGLtopology LineList = 1
    --data Geometry Lines a = Line a a

instance PrimitiveTopology Points where
    toGLtopology PointList = 0
    --data Geometry Points a = Point a

{-
Some day:

instance PrimitiveTopology TrianglesWithAdjacency where
    toGLtopology TriangleStripWithAdjacency = 0
    data Geometry TrianglesWithAdjacency a = TriangleWithAdjacency a a a a a a

instance PrimitiveTopology LinesWithAdjacency where
    toGLtopology LinesWithAdjacencyList = 0
    toGLtopology LinesWithAdjacencyStrip = 1
    data Geometry LinesWithAdjacency a = LineWithAdjacency a a a a
-}

type InstanceCount = Int

data PrimitiveArrayInt p a = PrimitiveArraySimple p Int a 
                           | PrimitiveArrayIndexed p IndexArray a 
                           | PrimitiveArrayInstanced p InstanceCount Int a 
                           | PrimitiveArrayIndexedInstanced p IndexArray InstanceCount a 

newtype PrimitiveArray p a = PrimitiveArray {getPrimitiveArray :: [PrimitiveArrayInt p a]}

instance Monoid (PrimitiveArray p a) where
    mempty = PrimitiveArray []
    mappend (PrimitiveArray a) (PrimitiveArray b) = PrimitiveArray (a ++ b)

instance Functor (PrimitiveArray p) where
    fmap f (PrimitiveArray xs) = PrimitiveArray  $ fmap g xs
        where g (PrimitiveArraySimple p l a) = PrimitiveArraySimple p l (f a)
              g (PrimitiveArrayIndexed p i a) = PrimitiveArrayIndexed p i (f a)
              g (PrimitiveArrayInstanced p il l a) = PrimitiveArrayInstanced p il l (f a)
              g (PrimitiveArrayIndexedInstanced p i il a) = PrimitiveArrayIndexedInstanced p i il (f a)
              
toPrimitiveArray :: PrimitiveTopology p => p -> VertexArray () a -> PrimitiveArray p a
toPrimitiveArray p va = PrimitiveArray [PrimitiveArraySimple p (vertexArrayLength va) (bArrBFunc va (BInput 0 0))]
toPrimitiveArrayIndexed :: PrimitiveTopology p => p -> IndexArray -> VertexArray () a -> PrimitiveArray p a
toPrimitiveArrayIndexed p ia va = PrimitiveArray [PrimitiveArrayIndexed p ia (bArrBFunc va (BInput 0 0))]
toPrimitiveArrayInstanced :: PrimitiveTopology p => p -> VertexArray () a -> VertexArray t b -> (a -> b -> c) -> PrimitiveArray p c
toPrimitiveArrayInstanced p va ina f = PrimitiveArray [PrimitiveArrayInstanced p (vertexArrayLength ina) (vertexArrayLength va) (f (bArrBFunc va $ BInput 0 0) (bArrBFunc ina $ BInput 0 1))]
toPrimitiveArrayIndexedInstanced :: PrimitiveTopology p => p -> IndexArray -> VertexArray () a -> VertexArray t b -> (a -> b -> c) -> PrimitiveArray p c
toPrimitiveArrayIndexedInstanced p ia va ina f = PrimitiveArray [PrimitiveArrayIndexedInstanced p ia (vertexArrayLength ina) (f (bArrBFunc va $ BInput 0 0) (bArrBFunc ina $ BInput 0 1))]