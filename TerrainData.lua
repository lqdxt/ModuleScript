--[[
 save it as a ModuleScript, preferably in ReplicatedStorage

 usage:

 local GetTerrain = require(game.ReplicatedStorage.TerrainData)
 local data = GetTerrain() <-- uses defaults: auto resolution, ignores water

 print(data.size) <-- Vector3 bounding size
 print(data.position) <-- center of the terrain
 print(data.slopes.average) <-- average slope in degrees
 print(data.slopes.min, data.slopes.max)

 -- query slope at a specific point:
 local slopeDeg, normal, groundY = data.slopes.get_slope_at(120, -340)
]]
--!strict
const Terrain = workspace.Terrain

export type TerrainData = {
 size: Vector3,
 position: Vector3,
 angles: Vector3,
 cframe: CFrame,
 bounds: {
  min: Vector3,
  max: Vector3,
 },
 slopes: {
  average: number,
  min: number,
  max: number,
  get_slope_at: (x: number, z: number) -> (number, Vector3, number?),
 },
 empty: boolean,
}

const MAX_SAMPLES: number = 4096
const YIELD_EVERY: number = 200

--- @param resolution: optional size in studs
--- @param ignoreWater: whether raycasts ignore water bodies
--- @param region: scan just your terrain's extents instead of Terrain.MaxExtents
--- @return TerrainData table containing measurements and slope statistics
const function GetTerrain(resolution: number?, ignoreWater: boolean?, region: { min: Vector3, max: Vector3 }?): TerrainData
 const skipWater: boolean = if ignoreWater ~= nil then ignoreWater else true
 if resolution ~= nil and resolution <= 0 then error("resolution must be a positive number") end

 local minExStuds: Vector3
 local maxExStuds: Vector3

 if region then
  minExStuds = region.min
  maxExStuds = region.max
 else
  const maxExtents: Region3int16 = Terrain.MaxExtents
  minExStuds = Vector3.new(maxExtents.Min.X * 4, maxExtents.Min.Y * 4, maxExtents.Min.Z * 4)
  maxExStuds = Vector3.new(maxExtents.Max.X * 4, maxExtents.Max.Y * 4, maxExtents.Max.Z * 4)
 end

 const spanX: number = maxExStuds.X - minExStuds.X
 const spanZ: number = maxExStuds.Z - minExStuds.Z

 local step: number = resolution or math.clamp(math.max(spanX, spanZ) / 50, 8, 64)

 const gridX: number = math.floor(spanX / step) + 1
 const gridZ: number = math.floor(spanZ / step) + 1
 if gridX * gridZ > MAX_SAMPLES then
  const scale: number = math.sqrt((gridX * gridZ) / MAX_SAMPLES)
  step *= scale
 end

 const params: RaycastParams = RaycastParams.new()
 params.FilterType = Enum.RaycastFilterType.Include
 params.FilterDescendantsInstances = { Terrain }
 params.IgnoreWater = skipWater

 const rStartY: number = maxExStuds.Y + 100
 const rDist: number = (maxExStuds.Y - minExStuds.Y) + 200

 local minX: number, minY: number, minZ: number = math.huge, math.huge, math.huge
 local maxX: number, maxY: number, maxZ: number = -math.huge, -math.huge, -math.huge

 local totalSlope: number = 0
 local minSlope: number = 90
 local maxSlope: number = 0
 local sampCount: number = 0
 local sumNormal: Vector3 = Vector3.zero
 local raysFired: number = 0

 for x: number = minExStuds.X, maxExStuds.X, step do
  for z: number = minExStuds.Z, maxExStuds.Z, step do
   const origin: Vector3 = Vector3.new(x, rStartY, z)
   const direction: Vector3 = Vector3.new(0, -rDist, 0)

   const hit: {
    Distance: number,
    Instance: BasePart,
    Material: Enum.Material,
    Normal: Vector3,
    Position: Vector3
   }? = workspace:Raycast(origin, direction, params)
   raysFired += 1
   if raysFired % YIELD_EVERY == 0 then
    task.wait()
   end
   if hit then
    const pos: Vector3 = hit.Position
    const normal: Vector3 = hit.Normal

    minX = math.min(minX, pos.X)
    minY = math.min(minY, pos.Y)
    minZ = math.min(minZ, pos.Z)

    maxX = math.max(maxX, pos.X)
    maxY = math.max(maxY, pos.Y)
    maxZ = math.max(maxZ, pos.Z)

    const dot: number = math.clamp(normal:Dot(Vector3.yAxis), -1, 1)
    const slopeDeg: number = math.deg(math.acos(dot))

    minSlope = math.min(minSlope, slopeDeg)
    maxSlope = math.max(maxSlope, slopeDeg)
    totalSlope += slopeDeg
    sumNormal += normal
    sampCount += 1
   end
  end
 end

 if sampCount == 0 then
  return {
   size = Vector3.zero,
   position = Vector3.zero,
   angles = Vector3.zero,
   cframe = CFrame.identity,
   bounds = { min = Vector3.zero, max = Vector3.zero },
   slopes = {
    average = 0,
    min = 0,
    max = 0,
    get_slope_at = function(x: number, z: number)
     return 0, Vector3.yAxis, nil
    end,
   },
   empty = true,
  }
 end

 const minBound: Vector3 = Vector3.new(minX, minY, minZ)
 const maxBound: Vector3 = Vector3.new(maxX, maxY, maxZ)
 const size: Vector3 = maxBound - minBound
 const position: Vector3 = (minBound + maxBound) / 2

 const avgNormal: Vector3 = sumNormal.Magnitude > 0 and sumNormal.Unit or Vector3.yAxis

 const upVector: Vector3 = avgNormal
 local forwVector: Vector3 = Vector3.zAxis
 if math.abs(upVector:Dot(forwVector)) > 0.99 then
  forwVector = Vector3.xAxis
 end
 const rightVector: Vector3 = upVector:Cross(forwVector).Unit
 forwVector = rightVector:Cross(upVector).Unit

 const terrCFrame: CFrame = CFrame.fromMatrix(position, rightVector, upVector, -forwVector)
 const rx: number, ry: number, rz: number = terrCFrame:ToOrientation()
 const angles: Vector3 = Vector3.new(math.deg(rx), math.deg(ry), math.deg(rz))

 const function get_slope_at(x: number, z: number): (number, Vector3, number?)
  const rayOrigin: Vector3 = Vector3.new(x, rStartY, z)
  const rayDir: Vector3 = Vector3.new(0, -rDist, 0)
  const hit: {
   Distance: number,
   Instance: BasePart,
   Material: Enum.Material,
   Normal: Vector3,
   Position: Vector3
  }? = workspace:Raycast(rayOrigin, rayDir, params)

  if hit then
   const dot: number = math.clamp(hit.Normal:Dot(Vector3.yAxis), -1, 1)
   const slopeDeg: number = math.deg(math.acos(dot))
   return slopeDeg, hit.Normal, hit.Position.Y
  end

  return 0, Vector3.yAxis, nil
 end

 return {
  size = size,
  position = position,
  angles = angles,
  cframe = terrCFrame,
  bounds = {
   min = minBound,
   max = maxBound,
  },
  slopes = {
   average = totalSlope / sampCount,
   min = minSlope,
   max = maxSlope,
   get_slope_at = get_slope_at,
  },
  empty = false,
 }
end

return GetTerrain
