import
  std/os,
  pathy, pixie

const
  Width = 96
  Height = 72
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

proc makeGrid(): seq[bool] =
  ## Builds the README drawing grid.
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
  route = Route(sx: 4, sy: 4, gx: 88, gy: 64)

drawPathSpace(grid, path, route)
drawTilePathSpace(grid, tiles, route)
drawJumpPointSpace(grid, jps, route)
drawBanner(grid, path, tiles, jps, route)
