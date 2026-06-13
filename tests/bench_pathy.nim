import
  std/random,
  benchy, pathy

const
  Width = 96
  Height = 72
  TileSize = 8
  RouteCount = 64
  ScanIterations = 20
  PrecomputeIterations = 5
  MinRouteDistance = 24

type
  Route = object
    sx: int
    sy: int
    gx: int
    gy: int

var Checksum = 0

proc gridIndex(width, x, y: int): int =
  ## Returns one flattened benchmark-grid index.
  y * width + x

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
  ## Sets a rectangular region in a benchmark grid.
  for yy in max(0, y) .. min(height - 1, y + h - 1):
    for xx in max(0, x) .. min(width - 1, x + w - 1):
      grid[gridIndex(width, xx, yy)] = value

proc makeGrid(): seq[bool] =
  ## Builds a deterministic benchmark grid with rooms and gaps.
  result = newSeq[bool](Width * Height)
  for i in 0 ..< result.len:
    result[i] = true
  result.setRect(Width, Height, 0, 0, Width, 1, false)
  result.setRect(Width, Height, 0, Height - 1, Width, 1, false)
  result.setRect(Width, Height, 0, 0, 1, Height, false)
  result.setRect(Width, Height, Width - 1, 0, 1, Height, false)

  for x in [18, 38, 58, 78]:
    result.setRect(Width, Height, x, 1, 2, Height - 2, false)
  result.setRect(Width, Height, 18, 8, 2, 6, true)
  result.setRect(Width, Height, 18, 42, 2, 8, true)
  result.setRect(Width, Height, 38, 18, 2, 8, true)
  result.setRect(Width, Height, 38, 56, 2, 8, true)
  result.setRect(Width, Height, 58, 6, 2, 8, true)
  result.setRect(Width, Height, 58, 34, 2, 8, true)
  result.setRect(Width, Height, 78, 24, 2, 8, true)
  result.setRect(Width, Height, 78, 54, 2, 8, true)

  for y in [16, 36, 56]:
    result.setRect(Width, Height, 1, y, Width - 2, 2, false)
  result.setRect(Width, Height, 4, 16, 8, 2, true)
  result.setRect(Width, Height, 28, 16, 8, 2, true)
  result.setRect(Width, Height, 64, 16, 8, 2, true)
  result.setRect(Width, Height, 84, 16, 8, 2, true)
  result.setRect(Width, Height, 20, 36, 8, 2, true)
  result.setRect(Width, Height, 45, 36, 8, 2, true)
  result.setRect(Width, Height, 71, 36, 8, 2, true)
  result.setRect(Width, Height, 10, 56, 8, 2, true)
  result.setRect(Width, Height, 40, 56, 8, 2, true)
  result.setRect(Width, Height, 70, 56, 8, 2, true)

  result.setRect(Width, Height, 8, 24, 8, 7, false)
  result.setRect(Width, Height, 27, 5, 7, 6, false)
  result.setRect(Width, Height, 48, 23, 6, 8, false)
  result.setRect(Width, Height, 64, 45, 7, 8, false)
  result.setRect(Width, Height, 82, 8, 6, 9, false)

proc randomPassable(path: PathSpace, rng: var Rand): PathStep =
  ## Returns one deterministic random passable point.
  for _ in 0 ..< 20_000:
    let
      x = rng.rand(path.width - 1)
      y = rng.rand(path.height - 1)
    if path.passable(x, y):
      return PathStep(found: true, x: x, y: y)
  path.firstPassable()

proc pathChecksum(path: openArray[PathStep]): int =
  ## Returns a small checksum for one path result.
  result = path.len
  if path.len > 0:
    result = result xor (path[0].x shl 1)
    result = result xor (path[path.high].y shl 2)

proc directDistance(route: Route): int =
  ## Returns the straight diagonal-aware distance for one route.
  pathHeuristic(DiagonalPath, route.sx, route.sy, route.gx, route.gy)

proc collectRoutes(path: PathSpace): seq[Route] =
  ## Collects route samples solvable by regular A*.
  var
    rng = initRand(12345)
    attempts = 0
  while result.len < RouteCount and attempts < 50_000:
    inc attempts
    let
      start = path.randomPassable(rng)
      goal = path.randomPassable(rng)
    if not start.found or not goal.found:
      continue
    if path.pathHeuristic(start.x, start.y, goal.x, goal.y) <
        MinRouteDistance:
      continue
    let pixelPath = path.findPath(start.x, start.y, goal.x, goal.y)
    if pixelPath.len == 0:
      continue
    result.add(Route(
      sx: start.x,
      sy: start.y,
      gx: goal.x,
      gy: goal.y
    ))
  if result.len == 0:
    raise newException(PathyError, "No benchmark routes found.")

proc printPathLine(
  name: string,
  solved,
  total,
  distance,
  baseline: int
) =
  ## Prints one path-distance summary row.
  echo name, " solved=", solved, "/", total,
    " pathDistance=", distance,
    " baseline=", baseline,
    " delta=", distance - baseline

proc printDistanceSummary(
  path: PathSpace,
  tiles: TilePathSpace,
  jps: JumpPointSpace,
  routes: openArray[Route]
) =
  ## Prints selected route and returned path distance totals.
  var
    directTotal = 0
    pixelTotal = 0
    tileTotal = 0
    jpsTotal = 0
    tileBaseline = 0
    jpsBaseline = 0
    tileSolved = 0
    jpsSolved = 0
  for route in routes:
    let
      pixelPath = path.findPath(route.sx, route.sy, route.gx, route.gy)
      tilePath = tiles.findPath(route.sx, route.sy, route.gx, route.gy)
      jpsPath = jps.findPath(route.sx, route.sy, route.gx, route.gy)
      pixelDistance = path.pathDistance(route.sx, route.sy, pixelPath)
    directTotal += route.directDistance()
    pixelTotal += pixelDistance
    if tilePath.len > 0:
      inc tileSolved
      tileTotal += tiles.pathDistance(route.sx, route.sy, tilePath)
      tileBaseline += pixelDistance
    if jpsPath.len > 0:
      inc jpsSolved
      jpsTotal += jps.pathDistance(route.sx, route.sy, jpsPath)
      jpsBaseline += pixelDistance
  echo "selected direct distance: ", directTotal
  printPathLine("regular A*", routes.len, routes.len, pixelTotal, pixelTotal)
  printPathLine("tile A*", tileSolved, routes.len, tileTotal, tileBaseline)
  printPathLine("JPS+", jpsSolved, routes.len, jpsTotal, jpsBaseline)
  echo "JPS+ missing: ", routes.len - jpsSolved

proc scanPath(
  path: PathSpace,
  routes: openArray[Route]
): int =
  ## Finds all sample routes with direct A*.
  for route in routes:
    let pathResult = path.findPath(route.sx, route.sy, route.gx, route.gy)
    result = result xor pathResult.pathChecksum()

proc scanTiles(
  tiles: TilePathSpace,
  routes: openArray[Route]
): int =
  ## Finds all sample routes with tile A*.
  for route in routes:
    let pathResult = tiles.findPath(route.sx, route.sy, route.gx, route.gy)
    result = result xor pathResult.pathChecksum()

proc scanJpsPlus(
  jps: JumpPointSpace,
  routes: openArray[Route]
): int =
  ## Finds all sample routes with JPS+.
  for route in routes:
    let pathResult = jps.findPath(route.sx, route.sy, route.gx, route.gy)
    result = result xor pathResult.pathChecksum()

let grid = makeGrid()
let
  path = newPathSpace(grid, Width, Height, DiagonalPath)
  tiles = newTilePathSpace(path, TileSize)
  jps = newJumpPointSpace(path)
  routes = collectRoutes(path)

echo "routes: ", routes.len, " tileSize: ", TileSize
echo "same route points are reused by all scan benchmarks"
printDistanceSummary(path, tiles, jps, routes)

timeIt "precompute tile A*", PrecomputeIterations:
  let fresh = newTilePathSpace(grid, Width, Height, TileSize, DiagonalPath)
  Checksum = Checksum xor fresh.nodes.len

timeIt "precompute JPS+", PrecomputeIterations:
  let fresh = newJumpPointSpace(grid, Width, Height, DiagonalPath)
  Checksum = Checksum xor fresh.jumps.len

timeIt "scan regular A*", ScanIterations:
  Checksum = Checksum xor path.scanPath(routes)

timeIt "scan tile A*", ScanIterations:
  Checksum = Checksum xor tiles.scanTiles(routes)

timeIt "scan JPS+", ScanIterations:
  Checksum = Checksum xor jps.scanJpsPlus(routes)

echo "checksum: ", Checksum
