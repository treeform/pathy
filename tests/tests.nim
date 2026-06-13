import
  std/random,
  pathy

type
  Route = object
    sx: int
    sy: int
    gx: int
    gy: int

proc gridIndex(width, x, y: int): int =
  ## Returns one flattened test-grid index.
  y * width + x

proc fillGrid(width, height: int, value = true): seq[bool] =
  ## Builds one filled test grid.
  result = newSeq[bool](width * height)
  for i in 0 ..< result.len:
    result[i] = value

proc setRect(
  grid: var seq[bool],
  width,
  height,
  x,
  y,
  w,
  h: int,
  value: bool
) =
  ## Sets a rectangular region in a test grid.
  for yy in max(0, y) .. min(height - 1, y + h - 1):
    for xx in max(0, x) .. min(width - 1, x + w - 1):
      grid[gridIndex(width, xx, yy)] = value

proc makeMaze(width, height: int): seq[bool] =
  ## Builds a deterministic room-like pathfinding test grid.
  result = fillGrid(width, height)
  result.setRect(width, height, 0, 0, width, 1, false)
  result.setRect(width, height, 0, height - 1, width, 1, false)
  result.setRect(width, height, 0, 0, 1, height, false)
  result.setRect(width, height, width - 1, 0, 1, height, false)

  result.setRect(width, height, 18, 1, 2, height - 2, false)
  result.setRect(width, height, 18, 8, 2, 6, true)
  result.setRect(width, height, 18, 42, 2, 6, true)
  result.setRect(width, height, 38, 1, 2, height - 2, false)
  result.setRect(width, height, 38, 20, 2, 6, true)
  result.setRect(width, height, 38, 50, 2, 6, true)
  result.setRect(width, height, 58, 1, 2, height - 2, false)
  result.setRect(width, height, 58, 6, 2, 6, true)
  result.setRect(width, height, 58, 33, 2, 6, true)

  result.setRect(width, height, 1, 16, width - 2, 2, false)
  result.setRect(width, height, 4, 16, 7, 2, true)
  result.setRect(width, height, 28, 16, 7, 2, true)
  result.setRect(width, height, 64, 16, 7, 2, true)
  result.setRect(width, height, 1, 36, width - 2, 2, false)
  result.setRect(width, height, 20, 36, 7, 2, true)
  result.setRect(width, height, 45, 36, 7, 2, true)
  result.setRect(width, height, 71, 36, 7, 2, true)

  result.setRect(width, height, 8, 24, 8, 7, false)
  result.setRect(width, height, 27, 5, 7, 6, false)
  result.setRect(width, height, 48, 23, 6, 8, false)
  result.setRect(width, height, 64, 45, 7, 8, false)

proc stepSign(value: int): int =
  ## Returns the sign for one path segment component.
  if value < 0:
    return -1
  if value > 0:
    return 1
  0

proc pathSegmentsValid(
  space: PathSpace,
  startX,
  startY: int,
  path: openArray[PathStep]
): bool =
  ## Returns true when all sparse path segments are walkable.
  var
    x = startX
    y = startY
  for step in path:
    while x != step.x or y != step.y:
      let
        dx = stepSign(step.x - x)
        dy = stepSign(step.y - y)
      if not space.pathStepPassable(x, y, dx, dy):
        return false
      x += dx
      y += dy
  true

proc pathEndsAt(
  path: openArray[PathStep],
  goalX,
  goalY: int
): bool =
  ## Returns true when a non-empty path ends at the requested goal.
  path.len > 0 and path[path.high].x == goalX and path[path.high].y == goalY

proc randomPassable(space: PathSpace, rng: var Rand): PathStep =
  ## Returns one deterministic random passable point.
  for _ in 0 ..< 20_000:
    let
      x = rng.rand(space.width - 1)
      y = rng.rand(space.height - 1)
    if space.passable(x, y):
      return PathStep(found: true, x: x, y: y)
  space.firstPassable()

proc testOpenGridModes() =
  ## Verifies open-grid distances for diagonal and cardinal modes.
  echo "Testing open grid modes"
  let
    diagonal = newPathSpace(12, 12, DiagonalPath)
    diagonalPath = diagonal.findPath(1, 1, 9, 6)
    cardinal = newPathSpace(12, 12, CardinalPath)
    cardinalPath = cardinal.findPath(1, 1, 9, 6)
  doAssert diagonalPath.pathEndsAt(9, 6)
  doAssert cardinalPath.pathEndsAt(9, 6)
  doAssert diagonal.pathDistance(1, 1, diagonalPath) == 8
  doAssert cardinal.pathDistance(1, 1, cardinalPath) == 13
  doAssert diagonal.pathSegmentsValid(1, 1, diagonalPath)
  doAssert cardinal.pathSegmentsValid(1, 1, cardinalPath)

proc testSpacesOnMaze(mode: PathMode) =
  ## Verifies all path spaces solve the same maze route.
  echo "Testing maze spaces in ", mode
  let
    width = 80
    height = 60
    grid = makeMaze(width, height)
    path = newPathSpace(grid, width, height, mode)
    tiles = newTilePathSpace(path, 8)
    jps = newJumpPointSpace(path)
    route = Route(sx: 4, sy: 4, gx: 74, gy: 54)
    pixelPath = path.findPath(route.sx, route.sy, route.gx, route.gy)
    tilePath = tiles.findPath(route.sx, route.sy, route.gx, route.gy)
    jpsPath = jps.findPath(route.sx, route.sy, route.gx, route.gy)
  doAssert pixelPath.pathEndsAt(route.gx, route.gy)
  doAssert tilePath.pathEndsAt(route.gx, route.gy)
  doAssert jpsPath.pathEndsAt(route.gx, route.gy)
  doAssert path.pathSegmentsValid(route.sx, route.sy, pixelPath)
  doAssert path.pathSegmentsValid(route.sx, route.sy, jpsPath)
  doAssert jps.pathDistance(route.sx, route.sy, jpsPath) ==
    path.pathDistance(route.sx, route.sy, pixelPath)
  doAssert tiles.pathDistance(route.sx, route.sy, tilePath) > 0

proc testUpdateRebuildsSpaces() =
  ## Verifies updates rebuild direct, tile, and JPS+ spaces.
  echo "Testing updates rebuild spaces"
  let
    width = 16
    height = 16
  var grid = fillGrid(width, height)
  let
    path = newPathSpace(grid, width, height, CardinalPath)
    tiles = newTilePathSpace(path, 4)
    jps = newJumpPointSpace(path)
  doAssert path.findPath(2, 2, 13, 2).len > 0
  grid.setRect(width, height, 7, 0, 1, height, false)
  path.update(grid)
  tiles.update(path)
  jps.update(path)
  doAssert path.findPath(2, 2, 13, 2).len == 0
  doAssert tiles.findPath(2, 2, 13, 2).len == 0
  doAssert jps.findPath(2, 2, 13, 2).len == 0
  grid.setRect(width, height, 7, 2, 1, 1, true)
  path.update(grid)
  tiles.update(path)
  jps.update(path)
  doAssert path.findPath(2, 2, 13, 2).pathEndsAt(13, 2)
  doAssert tiles.findPath(2, 2, 13, 2).pathEndsAt(13, 2)
  doAssert jps.findPath(2, 2, 13, 2).pathEndsAt(13, 2)

proc testJpsMatchesAStar(mode: PathMode) =
  ## Verifies JPS+ preserves exact A* distances on sampled routes.
  echo "Testing JPS+ matches A* in ", mode
  let
    width = 80
    height = 60
    grid = makeMaze(width, height)
    path = newPathSpace(grid, width, height, mode)
    jps = newJumpPointSpace(path)
  var
    rng = initRand(12345)
    tested = 0
    attempts = 0
  while tested < 32 and attempts < 20_000:
    inc attempts
    let
      start = path.randomPassable(rng)
      goal = path.randomPassable(rng)
    if path.pathHeuristic(start.x, start.y, goal.x, goal.y) < 20:
      continue
    let pixelPath = path.findPath(start.x, start.y, goal.x, goal.y)
    if pixelPath.len == 0:
      continue
    let jpsPath = jps.findPath(start.x, start.y, goal.x, goal.y)
    doAssert jpsPath.len > 0
    doAssert path.pathSegmentsValid(start.x, start.y, jpsPath)
    doAssert jps.pathDistance(start.x, start.y, jpsPath) ==
      path.pathDistance(start.x, start.y, pixelPath)
    inc tested
  doAssert tested == 32

testOpenGridModes()
testSpacesOnMaze(DiagonalPath)
testSpacesOnMaze(CardinalPath)
testUpdateRebuildsSpaces()
testJpsMatchesAStar(DiagonalPath)
testJpsMatchesAStar(CardinalPath)
