import
  std/[heapqueue, math]

const
  DefaultTileSize* = 8
  PathDeltas = [
    (dx: -1, dy: 0),
    (dx: 1, dy: 0),
    (dx: 0, dy: -1),
    (dx: 0, dy: 1),
    (dx: -1, dy: -1),
    (dx: 1, dy: -1),
    (dx: -1, dy: 1),
    (dx: 1, dy: 1)
  ]

type
  PathyError* = object of CatchableError

  PathMode* = enum
    CardinalPath,
    DiagonalPath

  PathStep* = object
    found*: bool
    x*: int
    y*: int

  PathSpace* = ref object
    ## A direct A-star path space over a passable grid.
    width*: int
    height*: int
    mode*: PathMode
    walkMask*: seq[bool]
    passableMask*: seq[bool]
    parents: seq[int]
    costs: seq[int]
    seen: seq[int]
    closed: seq[int]
    stamp: int

  TilePathSpace* = ref object
    ## A hybrid path space using coarse tiles and exact connectors.
    path*: PathSpace
    tileSize*: int
    width*: int
    height*: int
    nodes*: seq[PathStep]
    passableMask*: seq[bool]
    parents: seq[int]
    costs: seq[int]
    seen: seq[int]
    closed: seq[int]
    stamp: int

  JumpPointSpace* = ref object
    ## A JPS+ path space with precomputed jump distances.
    path*: PathSpace
    jumps*: seq[int]
    jumpMasks*: seq[uint8]
    blockedMasks*: seq[uint8]
    parents: seq[int]
    costs: seq[int]
    seen: seq[int]
    closed: seq[int]
    stamp: int

  JpsSpace* = JumpPointSpace

  PathNode = object
    priority: int
    index: int

  RabinDir = enum
    RabinDown,
    RabinDownRight,
    RabinRight,
    RabinUpRight,
    RabinUp,
    RabinUpLeft,
    RabinLeft,
    RabinDownLeft

proc `<`(a, b: PathNode): bool =
  ## Orders path nodes for Nim heapqueue.
  if a.priority == b.priority:
    return a.index < b.index
  a.priority < b.priority

proc signOf(value: int): int {.inline.} =
  ## Returns the sign of one integer.
  if value < 0:
    return -1
  if value > 0:
    return 1
  0

proc requireMask(
  walkMask: openArray[bool],
  width,
  height: int
) =
  ## Raises when a grid mask does not match its dimensions.
  if width <= 0 or height <= 0:
    raise newException(PathyError, "Path grid dimensions must be positive.")
  if walkMask.len != width * height:
    raise newException(
      PathyError,
      "Path grid mask length does not match width times height."
    )

proc directionCount(mode: PathMode): int {.inline.} =
  ## Returns how many movement directions one mode can use.
  case mode
  of CardinalPath:
    4
  of DiagonalPath:
    PathDeltas.len

proc pathIndex*(path: PathSpace, x, y: int): int {.inline.} =
  ## Returns one flattened path-space index.
  y * path.width + x

proc tileIndex*(tiles: TilePathSpace, x, y: int): int {.inline.} =
  ## Returns one flattened tile-space index.
  y * tiles.width + x

proc jumpIndex(jps: JumpPointSpace, x, y, dir: int): int {.inline.} =
  ## Returns one flattened jump-distance index.
  (y * jps.path.width + x) * PathDeltas.len + dir

proc inBounds*(path: PathSpace, x, y: int): bool {.inline.} =
  ## Returns true when a point is inside the path grid.
  x >= 0 and y >= 0 and x < path.width and y < path.height

proc inBounds*(tiles: TilePathSpace, x, y: int): bool {.inline.} =
  ## Returns true when a tile point is inside the tile grid.
  x >= 0 and y >= 0 and x < tiles.width and y < tiles.height

proc passable*(path: PathSpace, x, y: int): bool =
  ## Returns true when a point is inside the grid and passable.
  if not path.inBounds(x, y):
    return false
  path.passableMask[path.pathIndex(x, y)]

proc passable*(tiles: TilePathSpace, x, y: int): bool =
  ## Returns true when one tile has a passable representative point.
  if not tiles.inBounds(x, y):
    return false
  tiles.passableMask[tiles.tileIndex(x, y)]

proc update*(path: PathSpace, walkMask: openArray[bool]) =
  ## Replaces the path-space grid with a new walkability mask.
  requireMask(walkMask, path.width, path.height)
  path.walkMask = newSeq[bool](walkMask.len)
  path.passableMask = newSeq[bool](walkMask.len)
  for i in 0 ..< walkMask.len:
    path.walkMask[i] = walkMask[i]
    path.passableMask[i] = walkMask[i]
  path.parents.setLen(0)
  path.costs.setLen(0)
  path.seen.setLen(0)
  path.closed.setLen(0)
  path.stamp = 0

proc newPathSpace*(
  walkMask: openArray[bool],
  width,
  height: int,
  mode = DiagonalPath
): PathSpace =
  ## Creates a direct A-star path space over one walkability mask.
  requireMask(walkMask, width, height)
  new(result)
  result.width = width
  result.height = height
  result.mode = mode
  result.update(walkMask)

proc newPathSpace*(
  width,
  height: int,
  mode = DiagonalPath
): PathSpace =
  ## Creates a direct A-star path space where every point is passable.
  var walkMask = newSeq[bool](width * height)
  for i in 0 ..< walkMask.len:
    walkMask[i] = true
  newPathSpace(walkMask, width, height, mode)

proc pathHeuristic*(
  mode: PathMode,
  ax,
  ay,
  bx,
  by: int
): int =
  ## Returns the movement distance heuristic for one path mode.
  case mode
  of CardinalPath:
    abs(ax - bx) + abs(ay - by)
  of DiagonalPath:
    max(abs(ax - bx), abs(ay - by))

proc pathHeuristic*(
  path: PathSpace,
  ax,
  ay,
  bx,
  by: int
): int {.inline.} =
  ## Returns the path-space heuristic between two points.
  pathHeuristic(path.mode, ax, ay, bx, by)

{.push checks: off.}

proc passableFast(path: PathSpace, x, y: int): bool {.inline.} =
  ## Returns true when one point is inside the grid and passable.
  if x < 0 or y < 0 or x >= path.width or y >= path.height:
    return false
  path.passableMask[path.pathIndex(x, y)]

proc pathStepPassable*(
  path: PathSpace,
  x,
  y,
  dx,
  dy: int
): bool =
  ## Returns true when a unit path step can be taken.
  if dx == 0 and dy == 0:
    return false
  if abs(dx) > 1 or abs(dy) > 1:
    return false
  if dx != 0 and dy != 0 and path.mode == CardinalPath:
    return false
  let
    nx = x + dx
    ny = y + dy
  if not path.passable(nx, ny):
    return false
  if dx != 0 and dy != 0:
    if not path.passable(x + dx, y):
      return false
    if not path.passable(x, y + dy):
      return false
  true

proc pathStepPassableFast(
  path: PathSpace,
  x,
  y,
  dx,
  dy: int
): bool {.inline.} =
  ## Returns true when one unchecked JPS+ step can be taken.
  if dx != 0 and dy != 0 and path.mode == CardinalPath:
    return false
  let
    nx = x + dx
    ny = y + dy
  if not path.passableFast(nx, ny):
    return false
  if dx != 0 and dy != 0:
    if not path.passableFast(x + dx, y):
      return false
    if not path.passableFast(x, y + dy):
      return false
  true

proc reconstructPath(
  path: PathSpace,
  startIndex,
  goalIndex: int
): seq[PathStep] =
  ## Reconstructs a complete path from a parent table.
  var stepIndex = goalIndex
  while stepIndex != startIndex and stepIndex >= 0:
    result.add(PathStep(
      found: true,
      x: stepIndex mod path.width,
      y: stepIndex div path.width
    ))
    stepIndex = path.parents[stepIndex]
  for i in 0 ..< result.len div 2:
    swap(result[i], result[result.high - i])

proc resetSearch(path: PathSpace) =
  ## Prepares the stamped A-star scratch arrays for a new search.
  let area = path.width * path.height
  if path.parents.len != area:
    path.parents = newSeq[int](area)
    path.costs = newSeq[int](area)
    path.seen = newSeq[int](area)
    path.closed = newSeq[int](area)
    path.stamp = 0
  inc path.stamp
  if path.stamp == high(int):
    for i in 0 ..< area:
      path.seen[i] = 0
      path.closed[i] = 0
    path.stamp = 1

proc findPath*(
  path: PathSpace,
  startX,
  startY,
  goalX,
  goalY: int
): seq[PathStep] =
  ## Finds a complete A-star path between two points.
  if not path.passable(startX, startY) or
      not path.passable(goalX, goalY):
    return
  let
    startIndex = path.pathIndex(startX, startY)
    goalIndex = path.pathIndex(goalX, goalY)
  path.resetSearch()
  let stamp = path.stamp

  template touch(index: int) =
    if path.seen[index] != stamp:
      path.seen[index] = stamp
      path.parents[index] = -2
      path.costs[index] = high(int)

  var openSet: HeapQueue[PathNode]
  touch(startIndex)
  path.parents[startIndex] = -1
  path.costs[startIndex] = 0
  openSet.push(PathNode(
    priority: path.pathHeuristic(startX, startY, goalX, goalY),
    index: startIndex
  ))
  while openSet.len > 0:
    let current = openSet.pop()
    if path.closed[current.index] == stamp:
      continue
    if current.index == goalIndex:
      return path.reconstructPath(startIndex, goalIndex)
    path.closed[current.index] = stamp
    let
      x = current.index mod path.width
      y = current.index div path.width
    for dir in 0 ..< path.mode.directionCount:
      let
        delta = PathDeltas[dir]
        nx = x + delta.dx
        ny = y + delta.dy
      if not path.pathStepPassable(x, y, delta.dx, delta.dy):
        continue
      let nextIndex = path.pathIndex(nx, ny)
      if path.closed[nextIndex] == stamp:
        continue
      touch(nextIndex)
      let newCost = path.costs[current.index] + 1
      if newCost >= path.costs[nextIndex]:
        continue
      path.costs[nextIndex] = newCost
      path.parents[nextIndex] = current.index
      openSet.push(PathNode(
        priority: newCost + path.pathHeuristic(nx, ny, goalX, goalY),
        index: nextIndex
      ))

proc tileNode(
  path: PathSpace,
  x,
  y,
  size: int
): PathStep =
  ## Returns one representative passable point inside a tile.
  let
    centerX = min(path.width - 1, x + size div 2)
    centerY = min(path.height - 1, y + size div 2)
    maxX = min(path.width - 1, x + size - 1)
    maxY = min(path.height - 1, y + size - 1)
  if path.passable(centerX, centerY):
    return PathStep(found: true, x: centerX, y: centerY)
  var bestDistance = high(int)
  for yy in y .. maxY:
    for xx in x .. maxX:
      if not path.passable(xx, yy):
        continue
      let distance = path.pathHeuristic(centerX, centerY, xx, yy)
      if distance < bestDistance:
        bestDistance = distance
        result = PathStep(found: true, x: xx, y: yy)

proc rebuildTiles(tiles: TilePathSpace) =
  ## Rebuilds the coarse tile graph from the current path space.
  tiles.width = (tiles.path.width + tiles.tileSize - 1) div
    tiles.tileSize
  tiles.height = (tiles.path.height + tiles.tileSize - 1) div
    tiles.tileSize
  let area = tiles.width * tiles.height
  tiles.nodes = newSeq[PathStep](area)
  tiles.passableMask = newSeq[bool](area)
  for tileY in 0 ..< tiles.height:
    for tileX in 0 ..< tiles.width:
      let
        x = tileX * tiles.tileSize
        y = tileY * tiles.tileSize
        index = tiles.tileIndex(tileX, tileY)
        node = tiles.path.tileNode(x, y, tiles.tileSize)
      tiles.nodes[index] = node
      tiles.passableMask[index] = node.found
  tiles.parents.setLen(0)
  tiles.costs.setLen(0)
  tiles.seen.setLen(0)
  tiles.closed.setLen(0)
  tiles.stamp = 0

proc newTilePathSpace*(
  path: PathSpace,
  tileSize = DefaultTileSize
): TilePathSpace =
  ## Creates a tile path space from an existing path space.
  if tileSize <= 0:
    raise newException(PathyError, "Tile size must be positive.")
  new(result)
  result.path = path
  result.tileSize = tileSize
  result.rebuildTiles()

proc newTilePathSpace*(
  walkMask: openArray[bool],
  width,
  height: int,
  tileSize = DefaultTileSize,
  mode = DiagonalPath
): TilePathSpace =
  ## Creates a tile path space over one walkability mask.
  let path = newPathSpace(walkMask, width, height, mode)
  newTilePathSpace(path, tileSize)

proc update*(tiles: TilePathSpace, walkMask: openArray[bool]) =
  ## Replaces the base grid and rebuilds the tile path space.
  tiles.path.update(walkMask)
  tiles.rebuildTiles()

proc update*(tiles: TilePathSpace, path: PathSpace) =
  ## Replaces the base path space and rebuilds the tile path space.
  tiles.path = path
  tiles.rebuildTiles()

proc nearestTile(
  tiles: TilePathSpace,
  x,
  y: int,
  radius = 16
): PathStep =
  ## Returns the nearest passable tile around a tile coordinate.
  if tiles.passable(x, y):
    return PathStep(found: true, x: x, y: y)
  var bestDistance = high(int)
  for yy in max(0, y - radius) .. min(tiles.height - 1, y + radius):
    for xx in max(0, x - radius) .. min(tiles.width - 1, x + radius):
      if not tiles.passable(xx, yy):
        continue
      let distance = tiles.path.pathHeuristic(x, y, xx, yy)
      if distance < bestDistance:
        bestDistance = distance
        result = PathStep(found: true, x: xx, y: yy)

proc linePassable*(
  path: PathSpace,
  ax,
  ay,
  bx,
  by: int
): bool

proc tileStepPassable(
  tiles: TilePathSpace,
  x,
  y,
  dx,
  dy: int
): bool =
  ## Returns true when one tile step can be taken.
  if dx != 0 and dy != 0 and tiles.path.mode == CardinalPath:
    return false
  let
    nx = x + dx
    ny = y + dy
  if not tiles.passable(nx, ny):
    return false
  let
    current = tiles.nodes[tiles.tileIndex(x, y)]
    next = tiles.nodes[tiles.tileIndex(nx, ny)]
  if not tiles.path.linePassable(current.x, current.y, next.x, next.y):
    return false
  if dx != 0 and dy != 0:
    if not tiles.passable(x + dx, y):
      return false
    if not tiles.passable(x, y + dy):
      return false
  true

proc resetSearch(tiles: TilePathSpace) =
  ## Prepares the stamped tile A-star scratch arrays.
  let area = tiles.width * tiles.height
  if tiles.parents.len != area:
    tiles.parents = newSeq[int](area)
    tiles.costs = newSeq[int](area)
    tiles.seen = newSeq[int](area)
    tiles.closed = newSeq[int](area)
    tiles.stamp = 0
  inc tiles.stamp
  if tiles.stamp == high(int):
    for i in 0 ..< area:
      tiles.seen[i] = 0
      tiles.closed[i] = 0
    tiles.stamp = 1

proc reconstructPath(
  tiles: TilePathSpace,
  startIndex,
  goalIndex: int
): seq[PathStep] =
  ## Reconstructs a tile path as representative pixel points.
  var stepIndex = goalIndex
  while stepIndex != startIndex and stepIndex >= 0:
    result.add(tiles.nodes[stepIndex])
    stepIndex = tiles.parents[stepIndex]
  for i in 0 ..< result.len div 2:
    swap(result[i], result[result.high - i])

proc findCoarsePath(
  tiles: TilePathSpace,
  startTileX,
  startTileY,
  goalTileX,
  goalTileY: int
): seq[PathStep] =
  ## Finds a coarse A-star path between two tile points.
  let
    start = tiles.nearestTile(startTileX, startTileY)
    goal = tiles.nearestTile(goalTileX, goalTileY)
  if not start.found or not goal.found:
    return
  let
    startIndex = tiles.tileIndex(start.x, start.y)
    goalIndex = tiles.tileIndex(goal.x, goal.y)
  tiles.resetSearch()
  let stamp = tiles.stamp

  template touch(index: int) =
    if tiles.seen[index] != stamp:
      tiles.seen[index] = stamp
      tiles.parents[index] = -2
      tiles.costs[index] = high(int)

  var openSet: HeapQueue[PathNode]
  touch(startIndex)
  tiles.parents[startIndex] = -1
  tiles.costs[startIndex] = 0
  openSet.push(PathNode(
    priority: tiles.path.pathHeuristic(start.x, start.y, goal.x, goal.y),
    index: startIndex
  ))
  while openSet.len > 0:
    let current = openSet.pop()
    if tiles.closed[current.index] == stamp:
      continue
    if current.index == goalIndex:
      return tiles.reconstructPath(startIndex, goalIndex)
    tiles.closed[current.index] = stamp
    let
      x = current.index mod tiles.width
      y = current.index div tiles.width
    for dir in 0 ..< tiles.path.mode.directionCount:
      let
        delta = PathDeltas[dir]
        nx = x + delta.dx
        ny = y + delta.dy
      if not tiles.tileStepPassable(x, y, delta.dx, delta.dy):
        continue
      let nextIndex = tiles.tileIndex(nx, ny)
      if tiles.closed[nextIndex] == stamp:
        continue
      touch(nextIndex)
      let newCost = tiles.costs[current.index] + 1
      if newCost >= tiles.costs[nextIndex]:
        continue
      tiles.costs[nextIndex] = newCost
      tiles.parents[nextIndex] = current.index
      openSet.push(PathNode(
        priority: newCost + tiles.path.pathHeuristic(
          nx,
          ny,
          goal.x,
          goal.y
        ),
        index: nextIndex
      ))

proc appendPath(
  path: var seq[PathStep],
  segment: openArray[PathStep]
) =
  ## Appends one path segment while avoiding duplicate joins.
  for step in segment:
    if path.len > 0 and
        path[path.high].x == step.x and
        path[path.high].y == step.y:
      continue
    path.add(step)

proc pixelSegment(
  tiles: TilePathSpace,
  startX,
  startY,
  goalX,
  goalY: int
): tuple[found: bool, path: seq[PathStep]] =
  ## Finds one exact pixel connector segment.
  if startX == goalX and startY == goalY:
    return (found: true, path: @[])
  result.path = tiles.path.findPath(startX, startY, goalX, goalY)
  result.found = result.path.len > 0

proc findTilePath*(
  tiles: TilePathSpace,
  startX,
  startY,
  goalX,
  goalY: int
): seq[PathStep] =
  ## Finds a hybrid path using pixel connectors and coarse tile A-star.
  let
    rawStartX = clamp(startX div tiles.tileSize, 0, tiles.width - 1)
    rawStartY = clamp(startY div tiles.tileSize, 0, tiles.height - 1)
    rawGoalX = clamp(goalX div tiles.tileSize, 0, tiles.width - 1)
    rawGoalY = clamp(goalY div tiles.tileSize, 0, tiles.height - 1)
    start = tiles.nearestTile(rawStartX, rawStartY)
    goal = tiles.nearestTile(rawGoalX, rawGoalY)
  if not start.found or not goal.found:
    return tiles.path.findPath(startX, startY, goalX, goalY)

  let
    startIndex = tiles.tileIndex(start.x, start.y)
    goalIndex = tiles.tileIndex(goal.x, goal.y)
  if startIndex == goalIndex:
    return tiles.path.findPath(startX, startY, goalX, goalY)

  let
    startNode = tiles.nodes[startIndex]
    goalNode = tiles.nodes[goalIndex]
  var pre = tiles.pixelSegment(
    startX,
    startY,
    startNode.x,
    startNode.y
  )
  if not pre.found:
    return tiles.path.findPath(startX, startY, goalX, goalY)

  let coarse = tiles.findCoarsePath(start.x, start.y, goal.x, goal.y)
  if coarse.len == 0:
    return tiles.path.findPath(startX, startY, goalX, goalY)

  var post = tiles.pixelSegment(
    goalNode.x,
    goalNode.y,
    goalX,
    goalY
  )
  if not post.found:
    return tiles.path.findPath(startX, startY, goalX, goalY)

  result.appendPath(pre.path)
  result.appendPath(coarse)
  result.appendPath(post.path)

proc findPath*(
  tiles: TilePathSpace,
  startX,
  startY,
  goalX,
  goalY: int
): seq[PathStep] =
  ## Finds a hybrid tile path between two pixel points.
  tiles.findTilePath(startX, startY, goalX, goalY)

proc directionIndex(dx, dy: int): int =
  ## Returns the path direction index for one unit delta.
  for i in 0 ..< PathDeltas.len:
    if PathDeltas[i].dx == dx and PathDeltas[i].dy == dy:
      return i
  -1

proc ourDir(dir: RabinDir): int =
  ## Converts one Rabin direction to local path delta order.
  case dir
  of RabinDown:
    directionIndex(0, 1)
  of RabinDownRight:
    directionIndex(1, 1)
  of RabinRight:
    directionIndex(1, 0)
  of RabinUpRight:
    directionIndex(1, -1)
  of RabinUp:
    directionIndex(0, -1)
  of RabinUpLeft:
    directionIndex(-1, -1)
  of RabinLeft:
    directionIndex(-1, 0)
  of RabinDownLeft:
    directionIndex(-1, 1)

proc rabinDir(dx, dy: int): RabinDir =
  ## Converts one unit local direction to Rabin direction order.
  if dx == 0 and dy == 1:
    return RabinDown
  if dx == 1 and dy == 1:
    return RabinDownRight
  if dx == 1 and dy == 0:
    return RabinRight
  if dx == 1 and dy == -1:
    return RabinUpRight
  if dx == 0 and dy == -1:
    return RabinUp
  if dx == -1 and dy == -1:
    return RabinUpLeft
  if dx == -1 and dy == 0:
    return RabinLeft
  RabinDownLeft

proc pathDirMask(dir: RabinDir): uint8 {.inline.} =
  ## Returns one local path-direction bit for a Rabin direction.
  uint8(1 shl ourDir(dir))

proc addPathDir(mask: var uint8, dir: RabinDir) {.inline.} =
  ## Adds one Rabin direction to a local path-direction mask.
  mask = mask or pathDirMask(dir)

proc blocked(bits: uint8, dir: RabinDir): bool {.inline.} =
  ## Returns true when one Rabin direction is blocked at a node.
  (bits and uint8(1 shl ord(dir))) != 0

proc empty(bits: uint8, dir: RabinDir): bool {.inline.} =
  ## Returns true when one Rabin direction is open at a node.
  not bits.blocked(dir)

proc cardinalMask(
  dirs: array[5, RabinDir],
  straight,
  leftForced,
  rightForced,
  leftDiagonal,
  rightDiagonal: bool
): uint8 =
  ## Returns Rabin's cardinal direction-pruning mask.
  template add(i: int) =
    result.addPathDir(dirs[i])

  if straight and not leftForced and not rightForced:
    add(2)
  elif not straight and leftForced and not rightForced:
    add(0)
  elif not straight and not leftForced and rightForced:
    add(4)
  elif leftDiagonal and not rightForced:
    add(0)
    add(1)
    add(2)
  elif rightDiagonal and not leftForced:
    add(2)
    add(3)
    add(4)
  elif leftDiagonal and rightDiagonal:
    for i in 0 .. 4:
      add(i)
  elif straight and leftForced and
      not rightForced and not leftDiagonal:
    add(0)
    add(2)
  elif straight and not leftForced and
      rightForced and not rightDiagonal:
    add(2)
    add(4)
  elif not straight and leftForced and rightForced:
    add(0)
    add(4)
  elif straight and leftForced and rightForced and
      not leftDiagonal and not rightDiagonal:
    add(0)
    add(2)
    add(4)
  elif straight and leftForced and rightForced and
      leftDiagonal and not rightDiagonal:
    add(0)
    add(1)
    add(2)
    add(4)
  elif straight and leftForced and rightForced and
      not leftDiagonal and rightDiagonal:
    add(0)
    add(2)
    add(3)
    add(4)

proc diagonalMask(
  dirs: array[3, RabinDir],
  straight,
  leftish,
  rightish: bool
): uint8 =
  ## Returns Rabin's diagonal direction-pruning mask.
  template add(i: int) =
    result.addPathDir(dirs[i])

  if leftish and not rightish:
    add(0)
  elif not leftish and rightish:
    add(2)
  elif straight:
    add(0)
    add(1)
    add(2)
  elif leftish and rightish:
    add(0)
    add(2)

proc allowedMask(bits: uint8, parentDir: RabinDir): uint8 =
  ## Returns the local directions allowed by Rabin's JPS+ cases.
  case parentDir
  of RabinDown:
    let
      straight = bits.empty(RabinDown)
      leftForced = bits.blocked(RabinUpRight) and
        bits.empty(RabinRight)
      rightForced = bits.blocked(RabinUpLeft) and
        bits.empty(RabinLeft)
      leftDiagonal = leftForced and straight and
        bits.empty(RabinDownRight)
      rightDiagonal = rightForced and straight and
        bits.empty(RabinDownLeft)
    cardinalMask(
      [RabinRight, RabinDownRight, RabinDown,
        RabinDownLeft, RabinLeft],
      straight,
      leftForced,
      rightForced,
      leftDiagonal,
      rightDiagonal
    )
  of RabinDownRight:
    let
      leftish = bits.empty(RabinRight)
      rightish = bits.empty(RabinDown)
      straight = leftish and rightish and
        bits.empty(RabinDownRight)
    diagonalMask(
      [RabinRight, RabinDownRight, RabinDown],
      straight,
      leftish,
      rightish
    )
  of RabinRight:
    let
      straight = bits.empty(RabinRight)
      leftForced = bits.blocked(RabinUpLeft) and
        bits.empty(RabinUp)
      rightForced = bits.blocked(RabinDownLeft) and
        bits.empty(RabinDown)
      leftDiagonal = leftForced and straight and
        bits.empty(RabinUpRight)
      rightDiagonal = rightForced and straight and
        bits.empty(RabinDownRight)
    cardinalMask(
      [RabinUp, RabinUpRight, RabinRight,
        RabinDownRight, RabinDown],
      straight,
      leftForced,
      rightForced,
      leftDiagonal,
      rightDiagonal
    )
  of RabinUpRight:
    let
      leftish = bits.empty(RabinUp)
      rightish = bits.empty(RabinRight)
      straight = leftish and rightish and
        bits.empty(RabinUpRight)
    diagonalMask(
      [RabinUp, RabinUpRight, RabinRight],
      straight,
      leftish,
      rightish
    )
  of RabinUp:
    let
      straight = bits.empty(RabinUp)
      leftForced = bits.blocked(RabinDownLeft) and
        bits.empty(RabinLeft)
      rightForced = bits.blocked(RabinDownRight) and
        bits.empty(RabinRight)
      leftDiagonal = leftForced and straight and
        bits.empty(RabinUpLeft)
      rightDiagonal = rightForced and straight and
        bits.empty(RabinUpRight)
    cardinalMask(
      [RabinLeft, RabinUpLeft, RabinUp,
        RabinUpRight, RabinRight],
      straight,
      leftForced,
      rightForced,
      leftDiagonal,
      rightDiagonal
    )
  of RabinUpLeft:
    let
      leftish = bits.empty(RabinLeft)
      rightish = bits.empty(RabinUp)
      straight = leftish and rightish and
        bits.empty(RabinUpLeft)
    diagonalMask(
      [RabinLeft, RabinUpLeft, RabinUp],
      straight,
      leftish,
      rightish
    )
  of RabinLeft:
    let
      straight = bits.empty(RabinLeft)
      leftForced = bits.blocked(RabinDownRight) and
        bits.empty(RabinDown)
      rightForced = bits.blocked(RabinUpRight) and
        bits.empty(RabinUp)
      leftDiagonal = leftForced and straight and
        bits.empty(RabinDownLeft)
      rightDiagonal = rightForced and straight and
        bits.empty(RabinUpLeft)
    cardinalMask(
      [RabinDown, RabinDownLeft, RabinLeft,
        RabinUpLeft, RabinUp],
      straight,
      leftForced,
      rightForced,
      leftDiagonal,
      rightDiagonal
    )
  of RabinDownLeft:
    let
      leftish = bits.empty(RabinDown)
      rightish = bits.empty(RabinLeft)
      straight = leftish and rightish and
        bits.empty(RabinDownLeft)
    diagonalMask(
      [RabinDown, RabinDownLeft, RabinLeft],
      straight,
      leftish,
      rightish
    )

proc jumpBit(dir: int): uint8 {.inline.} =
  ## Returns the bit mask for one jump-point direction.
  uint8(1 shl dir)

proc isCardinalJumpPoint(
  path: PathSpace,
  x,
  y,
  dx,
  dy: int
): bool =
  ## Returns true when a cardinal movement reaches a jump point.
  if dx != 0 and dy != 0:
    return false
  if not path.passableFast(x, y):
    return false
  if not path.passableFast(x - dx, y - dy):
    return false
  let
    sideAX = x + dy
    sideAY = y + dx
    wallAX = x - dx + dy
    wallAY = y - dy + dx
    sideBX = x - dy
    sideBY = y - dx
    wallBX = x - dx - dy
    wallBY = y - dy - dx
  if path.passableFast(sideAX, sideAY) and
      not path.passableFast(wallAX, wallAY):
    return true
  if path.passableFast(sideBX, sideBY) and
      not path.passableFast(wallBX, wallBY):
    return true
  false

proc buildJumpPoints(path: PathSpace): seq[uint8] =
  ## Builds cardinal jump-point direction bits for every map point.
  result = newSeq[uint8](path.width * path.height)
  for y in 0 ..< path.height:
    for x in 0 ..< path.width:
      if not path.passableFast(x, y):
        continue
      let index = path.pathIndex(x, y)
      for dir in 0 ..< 4:
        let
          dx = PathDeltas[dir].dx
          dy = PathDeltas[dir].dy
        if path.isCardinalJumpPoint(x, y, dx, dy):
          result[index] = result[index] or jumpBit(dir)

proc setJump(
  jps: JumpPointSpace,
  x,
  y,
  dir,
  value: int
) =
  ## Writes one precomputed jump distance.
  jps.jumps[jps.jumpIndex(x, y, dir)] = value

proc fillCardinalJumps(
  jps: JumpPointSpace,
  jumpPoints: openArray[uint8]
) =
  ## Fills cardinal JPS+ jump distances with Rabin-style sweeps.
  let path = jps.path
  for y in 0 ..< path.height:
    var
      count = -1
      seen = false
    for x in 0 ..< path.width:
      if not path.passableFast(x, y):
        count = -1
        seen = false
        jps.setJump(x, y, directionIndex(-1, 0), 0)
        continue
      inc count
      if seen:
        jps.setJump(x, y, directionIndex(-1, 0), count)
      else:
        jps.setJump(x, y, directionIndex(-1, 0), -count)
      if (jumpPoints[path.pathIndex(x, y)] and
          jumpBit(directionIndex(-1, 0))) != 0:
        count = 0
        seen = true
    count = -1
    seen = false
    for x in countdown(path.width - 1, 0):
      if not path.passableFast(x, y):
        count = -1
        seen = false
        jps.setJump(x, y, directionIndex(1, 0), 0)
        continue
      inc count
      if seen:
        jps.setJump(x, y, directionIndex(1, 0), count)
      else:
        jps.setJump(x, y, directionIndex(1, 0), -count)
      if (jumpPoints[path.pathIndex(x, y)] and
          jumpBit(directionIndex(1, 0))) != 0:
        count = 0
        seen = true
  for x in 0 ..< path.width:
    var
      count = -1
      seen = false
    for y in 0 ..< path.height:
      if not path.passableFast(x, y):
        count = -1
        seen = false
        jps.setJump(x, y, directionIndex(0, -1), 0)
        continue
      inc count
      if seen:
        jps.setJump(x, y, directionIndex(0, -1), count)
      else:
        jps.setJump(x, y, directionIndex(0, -1), -count)
      if (jumpPoints[path.pathIndex(x, y)] and
          jumpBit(directionIndex(0, -1))) != 0:
        count = 0
        seen = true
    count = -1
    seen = false
    for y in countdown(path.height - 1, 0):
      if not path.passableFast(x, y):
        count = -1
        seen = false
        jps.setJump(x, y, directionIndex(0, 1), 0)
        continue
      inc count
      if seen:
        jps.setJump(x, y, directionIndex(0, 1), count)
      else:
        jps.setJump(x, y, directionIndex(0, 1), -count)
      if (jumpPoints[path.pathIndex(x, y)] and
          jumpBit(directionIndex(0, 1))) != 0:
        count = 0
        seen = true

proc fillDiagonalJump(jps: JumpPointSpace, dir: int) =
  ## Fills one diagonal JPS+ jump-distance plane.
  let
    path = jps.path
    dx = PathDeltas[dir].dx
    dy = PathDeltas[dir].dy
    horizontal = directionIndex(dx, 0)
    vertical = directionIndex(0, dy)
  var y =
    if dy < 0:
      0
    else:
      path.height - 1
  while y >= 0 and y < path.height:
    for x in 0 ..< path.width:
      if not path.passableFast(x, y) or
          not path.pathStepPassableFast(x, y, dx, dy):
        jps.setJump(x, y, dir, 0)
        continue
      let
        nx = x + dx
        ny = y + dy
        nextIndex = path.pathIndex(nx, ny)
      if jps.jumps[nextIndex * PathDeltas.len + horizontal] > 0 or
          jps.jumps[nextIndex * PathDeltas.len + vertical] > 0:
        jps.setJump(x, y, dir, 1)
        continue
      let nextDistance = jps.jumps[jps.jumpIndex(nx, ny, dir)]
      if nextDistance > 0:
        jps.setJump(x, y, dir, nextDistance + 1)
      else:
        jps.setJump(x, y, dir, nextDistance - 1)
    if dy < 0:
      inc y
    else:
      dec y

proc fillBlockedMasks(jps: JumpPointSpace) =
  ## Fills Rabin-order blocked-direction masks from jump distances.
  let path = jps.path
  jps.blockedMasks = newSeq[uint8](path.width * path.height)
  for y in 0 ..< path.height:
    for x in 0 ..< path.width:
      let index = path.pathIndex(x, y)
      if not path.passableFast(x, y):
        jps.blockedMasks[index] = high(uint8)
        continue
      var mask = 0'u8
      for dir in RabinDir:
        let localDir = ourDir(dir)
        if jps.jumps[index * PathDeltas.len + localDir] == 0:
          mask = mask or uint8(1 shl ord(dir))
      jps.blockedMasks[index] = mask

proc rebuildJumps(jps: JumpPointSpace) =
  ## Rebuilds all JPS+ tables from the current path space.
  let path = jps.path
  jps.jumps = newSeq[int](path.width * path.height * PathDeltas.len)
  jps.jumpMasks = path.buildJumpPoints()
  jps.fillCardinalJumps(jps.jumpMasks)
  if path.mode == DiagonalPath:
    for dir in 4 ..< PathDeltas.len:
      jps.fillDiagonalJump(dir)
  jps.fillBlockedMasks()
  jps.parents.setLen(0)
  jps.costs.setLen(0)
  jps.seen.setLen(0)
  jps.closed.setLen(0)
  jps.stamp = 0

proc newJumpPointSpace*(path: PathSpace): JumpPointSpace =
  ## Creates a JPS+ path space from an existing path space.
  new(result)
  result.path = path
  result.rebuildJumps()

proc newJumpPointSpace*(
  walkMask: openArray[bool],
  width,
  height: int,
  mode = DiagonalPath
): JumpPointSpace =
  ## Creates a JPS+ path space over one walkability mask.
  let path = newPathSpace(walkMask, width, height, mode)
  newJumpPointSpace(path)

proc newJpsSpace*(path: PathSpace): JpsSpace =
  ## Creates a JPS+ path space from an existing path space.
  newJumpPointSpace(path)

proc newJpsSpace*(
  walkMask: openArray[bool],
  width,
  height: int,
  mode = DiagonalPath
): JpsSpace =
  ## Creates a JPS+ path space over one walkability mask.
  newJumpPointSpace(walkMask, width, height, mode)

proc update*(jps: JumpPointSpace, walkMask: openArray[bool]) =
  ## Replaces the base grid and rebuilds the JPS+ path space.
  jps.path.update(walkMask)
  jps.rebuildJumps()

proc update*(jps: JumpPointSpace, path: PathSpace) =
  ## Replaces the base path space and rebuilds the JPS+ path space.
  jps.path = path
  jps.rebuildJumps()

proc rayDistance(
  ax,
  ay,
  bx,
  by,
  dx,
  dy: int
): int {.inline.} =
  ## Returns distance to a point when it lies on one movement ray.
  let
    vx = bx - ax
    vy = by - ay
  if dx == 0:
    if vx != 0 or vy * dy <= 0:
      return 0
    return abs(vy)
  if dy == 0:
    if vy != 0 or vx * dx <= 0:
      return 0
    return abs(vx)
  if abs(vx) != abs(vy):
    return 0
  if vx * dx <= 0 or vy * dy <= 0:
    return 0
  abs(vx)

proc jumpRaySucceeds(
  jps: JumpPointSpace,
  x,
  y,
  dx,
  dy,
  goalX,
  goalY: int
): bool {.inline.} =
  ## Returns true when a straight JPS ray finds a jump or the goal.
  let
    dir = directionIndex(dx, dy)
    goalDistance = rayDistance(x, y, goalX, goalY, dx, dy)
  if dir < 0:
    return false
  let distance = jps.jumps[jps.jumpIndex(x, y, dir)]
  if distance > 0:
    return true
  if goalDistance <= 0:
    return false
  if distance < 0 and goalDistance <= -distance:
    return true
  distance > 0 and goalDistance <= distance

proc jumpPlus(
  jps: JumpPointSpace,
  x,
  y,
  dir,
  goalX,
  goalY: int
): PathStep {.inline.} =
  ## Returns the next JPS+ jump point in one direction.
  let
    dx = PathDeltas[dir].dx
    dy = PathDeltas[dir].dy
    distance = jps.jumps[jps.jumpIndex(x, y, dir)]
  if distance == 0:
    return
  let limit = abs(distance)
  var bestDistance =
    if distance > 0:
      distance
    else:
      high(int)

  let goalDistance = rayDistance(x, y, goalX, goalY, dx, dy)
  if goalDistance > 0 and goalDistance <= limit:
    bestDistance = min(bestDistance, goalDistance)

  if jps.path.mode == DiagonalPath and dx != 0 and dy != 0:
    let
      toGoalX = goalX - x
      toGoalY = goalY - y
    if toGoalX * dx > 0:
      let projectionDistance = abs(toGoalX)
      if projectionDistance <= limit:
        let projectionY = y + dy * projectionDistance
        if jps.jumpRaySucceeds(
          goalX,
          projectionY,
          0,
          dy,
          goalX,
          goalY
        ):
          bestDistance = min(bestDistance, projectionDistance)
    if toGoalY * dy > 0:
      let projectionDistance = abs(toGoalY)
      if projectionDistance <= limit:
        let projectionX = x + dx * projectionDistance
        if jps.jumpRaySucceeds(
          projectionX,
          goalY,
          dx,
          0,
          goalX,
          goalY
        ):
          bestDistance = min(bestDistance, projectionDistance)
  elif jps.path.mode == CardinalPath:
    if dx != 0 and (goalX - x) * dx > 0:
      let projectionDistance = abs(goalX - x)
      if projectionDistance <= limit:
        let turnY = signOf(goalY - y)
        if turnY != 0 and jps.jumpRaySucceeds(
          goalX,
          y,
          0,
          turnY,
          goalX,
          goalY
        ):
          bestDistance = min(bestDistance, projectionDistance)
    if dy != 0 and (goalY - y) * dy > 0:
      let projectionDistance = abs(goalY - y)
      if projectionDistance <= limit:
        let turnX = signOf(goalX - x)
        if turnX != 0 and jps.jumpRaySucceeds(
          x,
          goalY,
          turnX,
          0,
          goalX,
          goalY
        ):
          bestDistance = min(bestDistance, projectionDistance)

  if bestDistance == high(int):
    return
  PathStep(
    found: true,
    x: x + dx * bestDistance,
    y: y + dy * bestDistance
  )

proc resetSearch(jps: JumpPointSpace) =
  ## Prepares the stamped JPS+ scratch arrays.
  let area = jps.path.width * jps.path.height
  if jps.parents.len != area:
    jps.parents = newSeq[int](area)
    jps.costs = newSeq[int](area)
    jps.seen = newSeq[int](area)
    jps.closed = newSeq[int](area)
    jps.stamp = 0
  inc jps.stamp
  if jps.stamp == high(int):
    for i in 0 ..< area:
      jps.seen[i] = 0
      jps.closed[i] = 0
    jps.stamp = 1

proc reconstructPath(
  jps: JumpPointSpace,
  startIndex,
  goalIndex: int
): seq[PathStep] =
  ## Reconstructs a JPS+ path from jump-point parents.
  var stepIndex = goalIndex
  while stepIndex != startIndex and stepIndex >= 0:
    result.add(PathStep(
      found: true,
      x: stepIndex mod jps.path.width,
      y: stepIndex div jps.path.width
    ))
    stepIndex = jps.parents[stepIndex]
  for i in 0 ..< result.len div 2:
    swap(result[i], result[result.high - i])

proc findJumpPath*(
  jps: JumpPointSpace,
  startX,
  startY,
  goalX,
  goalY: int
): seq[PathStep] =
  ## Finds a direct JPS+ path over precomputed jump edges.
  if jps.path.mode == CardinalPath:
    return jps.path.findPath(startX, startY, goalX, goalY)
  if not jps.path.passableFast(startX, startY) or
      not jps.path.passableFast(goalX, goalY):
    return
  let
    startIndex = jps.path.pathIndex(startX, startY)
    goalIndex = jps.path.pathIndex(goalX, goalY)
  jps.resetSearch()
  let stamp = jps.stamp

  template touch(index: int) =
    if jps.seen[index] != stamp:
      jps.seen[index] = stamp
      jps.parents[index] = -2
      jps.costs[index] = high(int)

  var openSet: HeapQueue[PathNode]
  touch(startIndex)
  jps.parents[startIndex] = -1
  jps.costs[startIndex] = 0
  openSet.push(PathNode(
    priority: jps.path.pathHeuristic(startX, startY, goalX, goalY),
    index: startIndex
  ))
  while openSet.len > 0:
    let current = openSet.pop()
    if jps.closed[current.index] == stamp:
      continue
    if current.index == goalIndex:
      return jps.reconstructPath(startIndex, goalIndex)
    jps.closed[current.index] = stamp
    let
      x = current.index mod jps.path.width
      y = current.index div jps.path.width
      parentIndex = jps.parents[current.index]
      dirMask =
        if parentIndex < 0 or jps.path.mode == CardinalPath:
          high(uint8)
        else:
          let
            parentX = parentIndex mod jps.path.width
            parentY = parentIndex div jps.path.width
            parentDir = rabinDir(
              signOf(x - parentX),
              signOf(y - parentY)
            )
          allowedMask(jps.blockedMasks[current.index], parentDir)
    for dir in 0 ..< jps.path.mode.directionCount:
      if (dirMask and uint8(1 shl dir)) == 0:
        continue
      let step = jps.jumpPlus(
        x,
        y,
        dir,
        goalX,
        goalY
      )
      if not step.found:
        continue
      let nextIndex = jps.path.pathIndex(step.x, step.y)
      if jps.closed[nextIndex] == stamp:
        continue
      touch(nextIndex)
      let newCost = jps.costs[current.index] +
        jps.path.pathHeuristic(x, y, step.x, step.y)
      if newCost >= jps.costs[nextIndex]:
        continue
      jps.costs[nextIndex] = newCost
      jps.parents[nextIndex] = current.index
      openSet.push(PathNode(
        priority: newCost + jps.path.pathHeuristic(
          step.x,
          step.y,
          goalX,
          goalY
        ),
        index: nextIndex
      ))

proc findPath*(
  jps: JumpPointSpace,
  startX,
  startY,
  goalX,
  goalY: int
): seq[PathStep] =
  ## Finds a path using JPS+ tables when diagonal movement is enabled.
  jps.findJumpPath(startX, startY, goalX, goalY)

{.pop.}

proc nearestPassable*(
  path: PathSpace,
  x,
  y: int,
  radius = 96
): PathStep =
  ## Returns the nearest passable point around a requested point.
  if path.passable(x, y):
    return PathStep(found: true, x: x, y: y)
  var bestDistance = high(int)
  for yy in max(0, y - radius) .. min(path.height - 1, y + radius):
    for xx in max(0, x - radius) .. min(path.width - 1, x + radius):
      if not path.passable(xx, yy):
        continue
      let distance = path.pathHeuristic(x, y, xx, yy)
      if distance < bestDistance:
        bestDistance = distance
        result = PathStep(found: true, x: xx, y: yy)

proc firstPassable*(path: PathSpace): PathStep =
  ## Returns the first passable point in map scan order.
  for y in 0 ..< path.height:
    for x in 0 ..< path.width:
      if path.passable(x, y):
        return PathStep(found: true, x: x, y: y)

proc linePassable*(
  path: PathSpace,
  ax,
  ay,
  bx,
  by: int
): bool =
  ## Returns true when a straight path segment stays walkable.
  if not path.passable(ax, ay):
    return false
  let
    dx = bx - ax
    dy = by - ay
    steps = max(abs(dx), abs(dy))
  if steps == 0:
    return path.passable(bx, by)
  var
    previousX = ax
    previousY = ay
  for i in 1 .. steps:
    let
      x = ax + int(round(float(dx) * float(i) / float(steps)))
      y = ay + int(round(float(dy) * float(i) / float(steps)))
      stepX = x - previousX
      stepY = y - previousY
    if stepX == 0 and stepY == 0:
      continue
    if abs(stepX) > 1 or abs(stepY) > 1:
      return false
    if not path.pathStepPassable(previousX, previousY, stepX, stepY):
      return false
    previousX = x
    previousY = y
  true

proc pathDistance*(
  mode: PathMode,
  startX,
  startY: int,
  path: openArray[PathStep]
): int =
  ## Returns the movement distance through one path.
  var
    x = startX
    y = startY
  for step in path:
    result += pathHeuristic(mode, x, y, step.x, step.y)
    x = step.x
    y = step.y

proc pathDistance*(
  space: PathSpace,
  startX,
  startY: int,
  path: openArray[PathStep]
): int =
  ## Returns the movement distance through one path.
  pathDistance(space.mode, startX, startY, path)

proc pathDistance*(
  tiles: TilePathSpace,
  startX,
  startY: int,
  path: openArray[PathStep]
): int =
  ## Returns the movement distance through one tile path.
  tiles.path.pathDistance(startX, startY, path)

proc pathDistance*(
  jps: JumpPointSpace,
  startX,
  startY: int,
  path: openArray[PathStep]
): int =
  ## Returns the movement distance through one JPS+ path.
  jps.path.pathDistance(startX, startY, path)

iterator all*(path: PathSpace): PathStep =
  ## Iterates all passable points in a path space.
  for y in 0 ..< path.height:
    for x in 0 ..< path.width:
      if path.passable(x, y):
        yield PathStep(found: true, x: x, y: y)

iterator all*(tiles: TilePathSpace): PathStep =
  ## Iterates all representative tile points in a tile space.
  for node in tiles.nodes:
    if node.found:
      yield node

iterator jumpPoints*(jps: JumpPointSpace): PathStep =
  ## Iterates all precomputed cardinal jump points.
  for y in 0 ..< jps.path.height:
    for x in 0 ..< jps.path.width:
      let index = jps.path.pathIndex(x, y)
      if jps.jumpMasks[index] != 0:
        yield PathStep(found: true, x: x, y: y)

proc jumpDistance*(
  jps: JumpPointSpace,
  x,
  y,
  dir: int
): int =
  ## Returns one precomputed jump distance for debugging or drawing.
  if dir < 0 or dir >= PathDeltas.len:
    raise newException(PathyError, "Jump direction is out of range.")
  if not jps.path.inBounds(x, y):
    raise newException(PathyError, "Jump point is outside the path grid.")
  jps.jumps[jps.jumpIndex(x, y, dir)]
