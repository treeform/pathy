import pathy

const
  Width = 16
  Height = 12

proc gridIndex(width, x, y: int): int =
  ## Returns one flattened example-grid index.
  y * width + x

var walkMask = newSeq[bool](Width * Height)
for i in 0 ..< walkMask.len:
  walkMask[i] = true

for y in 1 ..< Height - 1:
  if y != 6:
    walkMask[gridIndex(Width, 7, y)] = false

let
  path = newPathSpace(walkMask, Width, Height, DiagonalPath)
  tiles = newTilePathSpace(path, tileSize = 4)
  jps = newJumpPointSpace(path)

echo path.findPath(2, 2, 13, 9)
echo tiles.findPath(2, 2, 13, 9)
echo jps.findPath(2, 2, 13, 9)
