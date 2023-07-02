MathHelpers = {}

function MathHelpers.closest_yaw(angle, compared_angle)
    if angle - compared_angle > math.pi then
		return angle - 2 * math.pi
	elseif angle - compared_angle < -math.pi then
		return angle + 2 * math.pi
	end
	return angle
end

-- returns an angle in radians "close" to the given angle (less than 180 deg)
function MathHelpers.dir_to_yaw(dir, compared_angle)
	local dir_2d = vector.normalize(vector.new(dir.x, 0, dir.z))
	local angle = math.atan2(dir_2d.z, dir_2d.x)
	return MathHelpers.closest_yaw(angle, compared_angle)
end

 -- returns true if the angles (given in rad) are close, unwinding by one rotation if neccessary
function MathHelpers.angles_are_close(alpha, beta, threshold)
	return math.abs(alpha - beta) < threshold or
		math.abs(alpha - beta + 2 * math.pi) < threshold or
		math.abs(alpha - beta - 2 * math.pi) < threshold
end
