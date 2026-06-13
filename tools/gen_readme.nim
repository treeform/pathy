import
  std/[os, random],
  pathy, pixie

const
  Width = 96
  Height = 72
  MazeCols = 23
  MazeRows = 17
  MazeGridWidth = MazeCols * 2 + 1
  MazeGridHeight = MazeRows * 2 + 1
  MazeScale = 2
  MazeOffsetX = 1
  MazeOffsetY = 1
  Cell = 8.0'f32
  OriginX = 116.0'f32
  OriginY = 62.0'f32
  ImageWidth = 1000
  ImageHeight = 700
  Background = rgba(28, 36, 107, 255)
  WhiteSoft = rgba(255, 255, 255, 30)
  WhiteLine = rgba(255, 255, 255, 80)
  WhiteHard = rgba(255, 255, 255, 220)
  Green = rgba(0, 255, 0, 255)
  GreenSoft = rgba(0, 255, 0, 90)
  Red = rgba(255, 0, 0, 255)

type
  Route = object
    sx: int
    sy: int
    gx: int
    gy: int

proc gridIndex(width, x, y: int): int =
  ## Returns one flattened drawing-grid index.
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
  ## Sets a rectangular region in a drawing grid.
  for yy in max(0, y) .. min(height - 1, y + h - 1):
    for xx in max(0, x) .. min(width - 1, x + w - 1):
      grid[gridIndex(width, xx, yy)] = value

proc carveCell(
  maze: var seq[bool],
  x,
  y: int
) =
  ## Marks one logical maze grid point as open.
  maze[gridIndex(MazeGridWidth, x, y)] = true

proc carvePassage(
  maze: var seq[bool],
  fromX,
  fromY,
  toX,
  toY: int
) =
  ## Opens a passage between two adjacent maze cells.
  let
    ax = fromX * 2 + 1
    ay = fromY * 2 + 1
    bx = toX * 2 + 1
    by = toY * 2 + 1
  maze.carveCell(ax, ay)
  maze.carveCell((ax + bx) div 2, (ay + by) div 2)
  maze.carveCell(bx, by)

proc buildMaze(): seq[bool] =
  ## Builds a deterministic recursive-backtracker maze.
  result = newSeq[bool](MazeGridWidth * MazeGridHeight)
  var
    rng = initRand(314159)
    visited = newSeq[bool](MazeCols * MazeRows)
    stack = @[(x: 0, y: 0)]
  visited[0] = true
  result.carveCell(1, 1)

  while stack.len > 0:
    let current = stack[stack.high]
    var neighbors: seq[tuple[x, y: int]]
    for delta in [
      (x: -1, y: 0),
      (x: 1, y: 0),
      (x: 0, y: -1),
      (x: 0, y: 1)
    ]:
      let
        nx = current.x + delta.x
        ny = current.y + delta.y
      if nx < 0 or ny < 0 or nx >= MazeCols or ny >= MazeRows:
        continue
      if visited[gridIndex(MazeCols, nx, ny)]:
        continue
      neighbors.add((x: nx, y: ny))
    if neighbors.len == 0:
      discard stack.pop()
      continue
    let next = neighbors[rng.rand(neighbors.high)]
    result.carvePassage(current.x, current.y, next.x, next.y)
    visited[gridIndex(MazeCols, next.x, next.y)] = true
    stack.add(next)

proc addMazeLoops(maze: var seq[bool]) =
  ## Opens a few deterministic walls to make the maze less cramped.
  var rng = initRand(271828)
  for _ in 0 ..< 48:
    let
      cellX = rng.rand(MazeCols - 2) + 1
      cellY = rng.rand(MazeRows - 2) + 1
      horizontal = rng.rand(1) == 0
      x = cellX * 2 + 1
      y = cellY * 2 + 1
    if horizontal:
      maze.carveCell(x + 1, y)
    else:
      maze.carveCell(x, y + 1)

proc copyMaze(
  grid: var seq[bool],
  maze: openArray[bool]
) =
  ## Scales the logical maze into the drawing grid.
  for y in 0 ..< MazeGridHeight:
    for x in 0 ..< MazeGridWidth:
      let value = maze[gridIndex(MazeGridWidth, x, y)]
      for yy in 0 ..< MazeScale:
        for xx in 0 ..< MazeScale:
          grid[gridIndex(
            Width,
            MazeOffsetX + x * MazeScale + xx,
            MazeOffsetY + y * MazeScale + yy
          )] = value

proc openSpot(
  grid: var seq[bool],
  x,
  y: int
) =
  ## Opens a small start or goal spot in the maze grid.
  grid.setRect(Width, Height, x - 1, y - 1, 3, 3, true)

proc makeGrid(): seq[bool] =
  ## Builds the README drawing grid.
  result = newSeq[bool](Width * Height)
  var maze = buildMaze()
  maze.addMazeLoops()
  result.copyMaze(maze)
  result.setRect(Width, Height, 42, 28, 12, 10, false)
  result.setRect(Width, Height, 47, 28, 2, 10, true)
  result.setRect(Width, Height, 42, 32, 12, 2, true)
  result.openSpot(4, 4)
  result.openSpot(90, 68)

proc point(x, y: int): Vec2 =
  ## Converts one grid point to image space.
  vec2(
    OriginX + float32(x) * Cell + Cell / 2,
    OriginY + float32(y) * Cell + Cell / 2
  )

proc strokeLine(
  image: Image,
  a,
  b: Vec2,
  color: ColorRGBA,
  width = 2.0'f32
) =
  ## Draws one stroked line segment.
  let path = newPath()
  path.moveTo(a)
  path.lineTo(b)
  image.strokePath(path, color, strokeWidth = width)

proc strokeRect(
  image: Image,
  rect: Rect,
  color: ColorRGBA,
  width = 1.0'f32
) =
  ## Draws one stroked rectangle.
  let path = newPath()
  path.rect(rect)
  image.strokePath(path, color, strokeWidth = width)

proc fillRect(
  image: Image,
  rect: Rect,
  color: ColorRGBA
) =
  ## Draws one filled rectangle.
  let path = newPath()
  path.rect(rect)
  image.fillPath(path, color)

proc fillCircle(
  image: Image,
  center: Vec2,
  radius: float32,
  color: ColorRGBA
) =
  ## Draws one filled circle.
  let path = newPath()
  path.ellipse(center, radius, radius)
  image.fillPath(path, color)

proc drawGrid(image: Image, grid: openArray[bool]) =
  ## Draws the passability grid.
  image.fill(Background)
  for y in 0 ..< Height:
    for x in 0 ..< Width:
      if not grid[gridIndex(Width, x, y)]:
        image.fillRect(
          rect(
            OriginX + float32(x) * Cell,
            OriginY + float32(y) * Cell,
            Cell,
            Cell
          ),
          WhiteSoft
        )

proc drawTiles(image: Image, tiles: TilePathSpace) =
  ## Draws tile boundaries and tile representative points.
  for y in 0 ..< tiles.height:
    for x in 0 ..< tiles.width:
      image.strokeRect(
        rect(
          OriginX + float32(x * tiles.tileSize) * Cell,
          OriginY + float32(y * tiles.tileSize) * Cell,
          float32(tiles.tileSize) * Cell,
          float32(tiles.tileSize) * Cell
        ),
        WhiteLine,
        1.0
      )
  for node in tiles.all:
    image.fillCircle(point(node.x, node.y), 2, WhiteHard)

proc drawPath(
  image: Image,
  route: Route,
  path: openArray[PathStep],
  width = 3.0'f32
) =
  ## Draws one path as a connected green polyline.
  var previous = point(route.sx, route.sy)
  for step in path:
    let current = point(step.x, step.y)
    image.strokeLine(previous, current, Green, width)
    previous = current
  for step in path:
    image.fillCircle(point(step.x, step.y), 3, Green)
  image.fillCircle(point(route.sx, route.sy), 5, Red)
  image.fillCircle(point(route.gx, route.gy), 5, Green)

proc drawJumpPoints(
  image: Image,
  jps: JumpPointSpace,
  path: openArray[PathStep]
) =
  ## Draws all jump points and highlights those used by a path.
  for step in jps.jumpPoints:
    image.fillCircle(point(step.x, step.y), 2, WhiteHard)
  for step in path:
    image.fillCircle(point(step.x, step.y), 5, GreenSoft)
    image.fillCircle(point(step.x, step.y), 3, Green)

proc drawPathSpace(
  grid: openArray[bool],
  path: PathSpace,
  route: Route
) =
  ## Draws the direct A* path example.
  let pathResult = path.findPath(route.sx, route.sy, route.gx, route.gy)
  var image = newImage(ImageWidth, ImageHeight)
  image.drawGrid(grid)
  image.drawPath(route, pathResult)
  image.writeFile("examples/PathSpace.png")

proc drawTilePathSpace(
  grid: openArray[bool],
  tiles: TilePathSpace,
  route: Route
) =
  ## Draws the tile path example.
  let pathResult = tiles.findPath(route.sx, route.sy, route.gx, route.gy)
  var image = newImage(ImageWidth, ImageHeight)
  image.drawGrid(grid)
  image.drawTiles(tiles)
  image.drawPath(route, pathResult, 4.0)
  image.writeFile("examples/TilePathSpace.png")

proc drawJumpPointSpace(
  grid: openArray[bool],
  jps: JumpPointSpace,
  route: Route
) =
  ## Draws the JPS+ path example.
  let pathResult = jps.findPath(route.sx, route.sy, route.gx, route.gy)
  var image = newImage(ImageWidth, ImageHeight)
  image.drawGrid(grid)
  image.drawJumpPoints(jps, pathResult)
  image.drawPath(route, pathResult, 4.0)
  image.writeFile("examples/JumpPointSpace.png")

proc drawBanner(
  grid: openArray[bool],
  path: PathSpace,
  tiles: TilePathSpace,
  jps: JumpPointSpace,
  route: Route
) =
  ## Draws the banner by blending the three path styles together.
  let
    pathResult = path.findPath(route.sx, route.sy, route.gx, route.gy)
    tileResult = tiles.findPath(route.sx, route.sy, route.gx, route.gy)
    jpsResult = jps.findPath(route.sx, route.sy, route.gx, route.gy)
  var image = newImage(ImageWidth, 420)
  image.fill(Background)
  for y in 0 ..< Height:
    for x in 0 ..< Width:
      if not grid[gridIndex(Width, x, y)]:
        image.fillRect(
          rect(
            OriginX + float32(x) * Cell,
            20.0 + float32(y) * 5.0,
            Cell,
            5.0
          ),
          WhiteSoft
        )
  proc bannerPoint(x, y: int): Vec2 =
    vec2(OriginX + float32(x) * Cell + 4, 20 + float32(y) * 5 + 2)
  proc bannerPath(points: openArray[PathStep], width: float32) =
    var previous = bannerPoint(route.sx, route.sy)
    for step in points:
      let current = bannerPoint(step.x, step.y)
      image.strokeLine(previous, current, Green, width)
      previous = current
  bannerPath(pathResult, 2.0)
  bannerPath(tileResult, 4.0)
  bannerPath(jpsResult, 6.0)
  for step in jpsResult:
    image.fillCircle(bannerPoint(step.x, step.y), 4, Green)
  image.fillCircle(bannerPoint(route.sx, route.sy), 6, Red)
  image.fillCircle(bannerPoint(route.gx, route.gy), 6, Green)
  image.writeFile("docs/pathyBanner.png")

createDir("docs")
createDir("examples")

let
  grid = makeGrid()
  path = newPathSpace(grid, Width, Height, DiagonalPath)
  tiles = newTilePathSpace(path, DefaultTileSize)
  jps = newJumpPointSpace(path)
  route = Route(sx: 4, sy: 4, gx: 90, gy: 68)

doAssert not path.linePassable(route.sx, route.sy, route.gx, route.gy)
doAssert path.findPath(route.sx, route.sy, route.gx, route.gy).len > 0
doAssert tiles.findPath(route.sx, route.sy, route.gx, route.gy).len > 0
doAssert jps.findPath(route.sx, route.sy, route.gx, route.gy).len > 0

drawPathSpace(grid, path, route)
drawTilePathSpace(grid, tiles, route)
drawJumpPointSpace(grid, jps, route)
drawBanner(grid, path, tiles, jps, route)
