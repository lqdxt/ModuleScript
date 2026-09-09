--!strict
local Terrain = workspace.Terrain

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
  getSlopeAt: (x: number, z: number) -> (number, Vector3, number?),
 },
 isEmpty: boolean,
}

--- @param resolution number? optional step size in studs (default: auto-calculated for optimal speed)
--- @param ignoreWater boolean? whether raycasts ignore water bodies (default: true)
function GetTerrain(resolution: number?, ignoreWater: boolean?): TerrainData
 local skipWater = if ignoreWater ~= nil then ignoreWater else true

 local maxExtents = Terrain.MaxExtents
 local minExtentsStuds = Vector3.new(maxExtents.Min.X * 4, maxExtents.Min.Y * 4, maxExtents.Min.Z * 4)
 local maxExtentsStuds = Vector3.new(maxExtents.Max.X * 4, maxExtents.Max.Y * 4, maxExtents.Max.Z * 4)

 local spanX = maxExtentsStuds.X - minExtentsStuds.X
 local spanZ = maxExtentsStuds.Z - minExtentsStuds.Z

 local step = resolution or math.clamp(math.max(spanX, spanZ) / 50, 8, 64)

 local raycastParams = RaycastParams.new()
 raycastParams.FilterType = Enum.RaycastFilterType.Include
 raycastParams.FilterDescendantsInstances = { Terrain }
 raycastParams.IgnoreWater = skipWater

 local rayStartY = maxExtentsStuds.Y + 100
 local rayDistance = (maxExtentsStuds.Y - minExtentsStuds.Y) + 200

 local minX, minY, minZ = math.huge, math.huge, math.huge
 local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge

 local totalSlope = 0
 local minSlope = 90
 local maxSlope = 0
 local sampledCount = 0
 local sumNormal = Vector3.zero

 for x = minExtentsStuds.X, maxExtentsStuds.X, step do
  for z = minExtentsStuds.Z, maxExtentsStuds.Z, step do
   local origin = Vector3.new(x, rayStartY, z)
   local direction = Vector3.new(0, -rayDistance, 0)

   local hit = workspace:Raycast(origin, direction, raycastParams)
   if hit then
    local pos = hit.Position
    local normal = hit.Normal

    minX = math.min(minX, pos.X)
    minY = math.min(minY, pos.Y)
    minZ = math.min(minZ, pos.Z)

    maxX = math.max(maxX, pos.X)
    maxY = math.max(maxY, pos.Y)
    maxZ = math.max(maxZ, pos.Z)

    local dot = math.clamp(normal:Dot(Vector3.yAxis), -1, 1)
    local slopeDeg = math.deg(math.acos(dot))

    minSlope = math.min(minSlope, slopeDeg)
    maxSlope = math.max(maxSlope, slopeDeg)
    totalSlope += slopeDeg
    sumNormal += normal
    sampledCount += 1
   end
  end
 end

 if sampledCount == 0 then
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
    getSlopeAt = function(x: number, z: number)
     return 0, Vector3.yAxis, nil
    end,
   },
   isEmpty = true,
  }
 end

 local minBound = Vector3.new(minX, minY, minZ)
 local maxBound = Vector3.new(maxX, maxY, maxZ)
 local size = maxBound - minBound
 local position = (minBound + maxBound) / 2

 local avgNormal = sumNormal.Magnitude > 0 and sumNormal.Unit or Vector3.yAxis

 local upVector = avgNormal
 local forwardVector = Vector3.zAxis
 if math.abs(upVector:Dot(forwardVector)) > 0.99 then
  forwardVector = Vector3.xAxis
 end
 local rightVector = upVector:Cross(forwardVector).Unit
 forwardVector = rightVector:Cross(upVector).Unit

 local terrainCFrame = CFrame.fromMatrix(position, rightVector, upVector, -forwardVector)
 local rx, ry, rz = terrainCFrame:ToOrientation()
 local angles = Vector3.new(math.deg(rx), math.deg(ry), math.deg(rz))

 local function getSlopeAt(x: number, z: number): (number, Vector3, number?)
  local rayOrigin = Vector3.new(x, rayStartY, z)
  local rayDirection = Vector3.new(0, -rayDistance, 0)
  local hit = workspace:Raycast(rayOrigin, rayDirection, raycastParams)

  if hit then
   local dot = math.clamp(hit.Normal:Dot(Vector3.yAxis), -1, 1)
   local slopeDeg = math.deg(math.acos(dot))
   return slopeDeg, hit.Normal, hit.Position.Y
  end

  return 0, Vector3.yAxis, nil
 end

 return {
  size = size,
  position = position,
  angles = angles,
  cframe = terrainCFrame,
  bounds = {
   min = minBound,
   max = maxBound,
  },
  slopes = {
   average = totalSlope / sampledCount,
   min = minSlope,
   max = maxSlope,
   getSlopeAt = getSlopeAt,
  },
  isEmpty = false,
 }
end

return GetTerrain
