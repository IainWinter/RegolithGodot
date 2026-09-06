#include "MarchingSquares.h"
#include "Math/FuzzyEqual.h"

#include "Math/Hash.h"
#include "Math/MathUtil.h"

#include "glm/geometric.hpp"

#include "earcut.hpp"


#include <unordered_map>

std::vector<vec2> marching_squares(int width, int height, const ArrayView<SpriteCellMask>& mask) {

	std::vector<vec2> edges;

    for (int y = -1; y < height; y++)
    for (int x = -1; x < width; x++) {
        //  p4---v3---p3
        //  |         |
        //  v4        v2
        //  |         |
        //  p1---v1---p2

		int p1Index = x + y * width;
		int p2Index = p1Index + 1;
		int p3Index = p1Index + 1 + width;
		int p4Index = p1Index + width;

		int nx = x + 1;
		int ny = y + 1;

        bool p1 =  x >= 0    && y >= 0      && mask[p1Index].is_filled();
        bool p2 = nx < width && y >= 0      && mask[p2Index].is_filled();
        bool p3 = nx < width && ny < height && mask[p3Index].is_filled();
        bool p4 =  x >= 0    && ny < height && mask[p4Index].is_filled();

        vec2 v1 = vec2(x + 0.5f, y);
        vec2 v2 = vec2(x + 1.0f, y + 0.5f);
        vec2 v3 = vec2(x + 0.5f, y + 1.0f);
        vec2 v4 = vec2(x,        y + 0.5f);

        int config = 0;
        if (p1) config |= 1;
        if (p2) config |= 2;
        if (p3) config |= 4;
        if (p4) config |= 8;

		// This generates a counter-clockwise winding order

        switch (config) {
		case 1:
			edges.push_back(v1);
			edges.push_back(v4);
			break;
		case 2:
			edges.push_back(v2);
			edges.push_back(v1);
			break;
		case 3:
			edges.push_back(v2);
			edges.push_back(v4);
			break;
		case 4:
			edges.push_back(v3);
			edges.push_back(v2);
			break;
		case 5:
			edges.push_back(v1);
			edges.push_back(v2);
			edges.push_back(v3);
			edges.push_back(v4);
			break;
		case 6:
			edges.push_back(v3);
			edges.push_back(v1);
			break;
		case 7:
			edges.push_back(v3);
			edges.push_back(v4);
			break;
		case 8:
			edges.push_back(v4);
			edges.push_back(v3);
			break;
		case 9:
			edges.push_back(v1);
			edges.push_back(v3);
			break;
		case 10:
			edges.push_back(v4);
			edges.push_back(v1);
			edges.push_back(v2);
			edges.push_back(v3);
			break;
		case 11:
			edges.push_back(v2);
			edges.push_back(v3);
			break;
		case 12:
			edges.push_back(v4);
			edges.push_back(v2);
			break;
		case 13:
			edges.push_back(v1);
			edges.push_back(v2);
			break;
		case 14:
			edges.push_back(v4);
			edges.push_back(v1);
			break;
		default:
			break;
		}
    }

    return edges;
}


#pragma region unused

// Function to determine if a point is inside a polygon
static bool isPointInPolygon(const vec2& point, const std::vector<vec2>& polygon) {
    int n = int(polygon.size());
    bool inside = false;
    for (int i = 0, j = n - 1; i < n; j = i++) {
        if (((polygon[i].y > point.y) != (polygon[j].y > point.y)) &&
            (point.x < (polygon[j].x - polygon[i].x) * (point.y - polygon[i].y) / (polygon[j].y - polygon[i].y) + polygon[i].x)) {
            inside = !inside;
        }
    }
    return inside;
}

// Function to compute the perpendicular distance from a point to a line
static float perpendicularDistance(const vec2& point, const vec2& lineStart, const vec2& lineEnd) {
    float lineLengthSquared = length(lineEnd - lineStart) * length(lineEnd - lineStart);
    if (lineLengthSquared == 0.0f) {
        return length(point - lineStart);
    }
    
    float t = dot(point - lineStart, lineEnd - lineStart) / lineLengthSquared;
    t = glm::clamp(t, 0.0f, 1.0f);
    vec2 projection = lineStart + t * (lineEnd - lineStart);
    return length(point - projection);
}

// Ramer–Douglas–Peucker recursive function
void RDP(const std::vector<vec2>& points, float epsilon, std::vector<vec2>& result) {
    if (points.size() < 2) {
        return;
    }

    // Find the point with the maximum perpendicular distance
    float maxDistance = 0.0f;
    size_t index = 0;

    for (size_t i = 1; i < points.size() - 1; ++i) {
        float distance = perpendicularDistance(points[i], points[0], points.back());
        if (distance > maxDistance) {
            index = i;
            maxDistance = distance;
        }
    }

    // If the max distance is greater than epsilon, recursively simplify
    if (maxDistance > epsilon) {
        // Divide the curve into two parts and recursively simplify
        std::vector<vec2> left(points.begin(), points.begin() + index + 1);
        std::vector<vec2> right(points.begin() + index, points.end());

        std::vector<vec2> leftResult;
        std::vector<vec2> rightResult;

        RDP(left, epsilon, leftResult);
        RDP(right, epsilon, rightResult);

        // Combine results: exclude the duplicate middle point
        result.insert(result.end(), leftResult.begin(), leftResult.end() - 1);
        result.insert(result.end(), rightResult.begin(), rightResult.end());
    } else {
        // If no point is farther than epsilon, the start and end points are enough
        result.push_back(points[0]);
        result.push_back(points.back());
    }
}

// Simplify function
std::vector<vec2> simplify(const std::vector<vec2>& points, float epsilon) {
    if (points.size() < 2) {
        return points;
    }

    std::vector<vec2> result;
    RDP(points, epsilon, result);
    return result;
}

#pragma endregion

std::vector<std::vector<std::vector<vec2>>> MarchingSquares_CreateChains(const std::vector<vec2>& edges) {

	// 1. Create a lookup table for each edge

	std::unordered_map<vec2, vec2> segments; // begin -> end
	for (size_t i = 1; i < edges.size(); i += 2) {
		segments.emplace(edges[i - 1] + 0.5f, edges[i] + 0.5f);
	}

	// 2. Use the segments basically as a stack to process until it's empty.
	//    If a chain connects to itself, it must be a loop. There may be multiple
	//    loops in the list of edges, so keep processing. All loops must connect
	//    or this will loop forever, but marching squares guarantees this condition.

	std::vector<std::vector<vec2>> chains;

	while (segments.size() > 0) {
		// 2.1. Until there are no more segments keep creating chains
		//      seed with the first segment.

		std::vector<vec2> chain;
		{
			auto itr = segments.begin();
			chain.push_back(itr->first);
			chain.push_back(itr->second);
			segments.erase(itr);
		}

		// 2.2. Keep adding segments to this chain until it connects to itself

		while (chain.front() != chain.back()) {
			// 2.3. Triangles are expensive for box2d, so reducing the number points is critical
			//      Two cases which come to mind to remove are, colinear points and 90-degree corners.
			//
			//      When adding p0,
			//        2.3.1. colinear: Detect if the points (p2, p1, p0) are colinear by using cross(p1-p0, p2-p1) ~ 0.f
			//                  Then replace p1 with p0
			//
			//		  2.3.2. 90-degree: Detect if the points (p3, p2, p1, p0) could form a 90 degree angle by Dot(p2-p3, p0-p1) ~ 0.f
			//                   Then replace p1 and p2 with a new point ast the intersection point of p2-p3 and p0-p1
			//
			//        2.3.3: End cap >: Detect if the points (p3, p4, p2, p1, p0) for an 'endcap' which is a bar 1 pixel wide
			//                          Then replace (p3, p4, p2, p1, p0) with (p3, p4, p1, p0)

			vec2 p2 = chain.at(chain.size() - 2);
			vec2 p1 = chain.at(chain.size() - 1);

			vec2 p0;
			{
				auto itr = segments.find(p1);
				p0 = itr->second;
				segments.erase(itr);
			}

			// 2.3.1. colinear (p2 -> p1) == (p1 <- p0)
			//        Vectors are reversed for 2.3.2

			vec2 v10 = p1 - p0;
			vec2 v21 = p1 - p2;

			bool colinear = equal(cross(v10, v21), 0.f);

			if (colinear) {
				chain.back() = p0;
				continue;
			}

			// 2.3.2. Can only run this if there are 4 points
			//        Annoying that this if statement has to be run everytime, could unroll. plz compiler :)
			//        Looks like some rotation / reflection of this
			//              p1 -> p0          p1 --> p0
			//            p2              ->  ^
			//            ^                   |
			//            p3                  p3

			if (chain.size() > 2) {
				vec2 p3 = chain.at(chain.size() - 3);

				vec2 v32 = p2 - p3;

				bool corner =  (v10.x == 0.f || v10.y == 0.f)
							&& (v32.x == 0.f || v32.y == 0.f);

				float determinant = v10.x * v32.y - v10.y * v32.x;
				float distSqr21 = dot(v21, v21); // only consider close points

				if (corner && !equal(determinant, 0.f) && distSqr21 < 1.f) {
					vec2 delta = p3 - p0;
					float t = (delta.x * v32.y - delta.y * v32.x) / determinant;
					vec2 intersection = p0 + t * v10;

					chain.pop_back();
					chain.back() = intersection;
				}
			}

			// 2.3.2. Can only run this if there are 5 points
			//        Collapse end caps which contain 3 points into 2 corner points
			//        Also looks like some rotation / reflection of this
			//           p1 -> p0        p1 ----> p0
			//        p2             ->  ^
			//           p3 <- p4        p3 <---- p4

			if (chain.size() > 3) {
				vec2 p3 = chain.at(chain.size() - 3);
				vec2 p4 = chain.at(chain.size() - 4);

				vec2 v32 = p2 - p3;
				vec2 v43 = p3 - p4;

				float determinant = v10.x * v43.y - v10.y * v43.x;

				bool tunnel = equal(determinant, 0.f);
				bool endcap = equal(dot(v21, v32), 0.f);

				float distSqr21 = dot(v21, v21); // only consider close points
				float distSqr32 = dot(v32, v32);

				if (tunnel && endcap && distSqr21 < 1.f && distSqr32 < 1.f) {
					vec2 new0;
					vec2 new1;

					// Figure out which direction this cap is
					if (v10.x == 0.f) {
						new0 = vec2(p3.x, p2.y);
						new1 = vec2(p1.x, p2.y);
					}

					else {
						new0 = vec2(p2.x, p3.y);
						new1 = vec2(p2.x, p1.y);
					}

					chain.pop_back();
					chain.at(chain.size() - 2) = new0;
					chain.at(chain.size() - 1) = new1;
				}
			}

			chain.push_back(p0);
		}

		// 3. Clean up final link in chain

		// 3.1 We looped until the front == back, so remove the back
		chain.pop_back();

		// 3.2 Test if starting point is colinear
		//
		{
			vec2 p2 = chain.at(chain.size() - 1);
			vec2 p1 = chain.at(0);
			vec2 p0 = chain.at(1);

			vec2 v10 = p1 - p0;
			vec2 v21 = p1 - p2;

			bool colinear = equal(cross(v10, v21), 0.f);

			if (colinear) {
				// can this not swap and pop the back point somehow?
				chain.erase(chain.begin()); // bad copying
			}
		}

		// 3.3 Test if starting point is a corner
		//     There are two cases for this

		// case 1
		{
			vec2 p3 = chain.at(chain.size() - 2);
			vec2 p2 = chain.at(chain.size() - 1);
			vec2 p1 = chain.at(0);
			vec2 p0 = chain.at(1);

			vec2 v10 = p1 - p0;
			vec2 v32 = p2 - p3;

			bool corner =  (v10.x == 0.f || v10.y == 0.f)
						&& (v32.x == 0.f || v32.y == 0.f);

			float determinant = v10.x * v32.y - v10.y * v32.x;

			float dist = distance(p1, p2);

			if (corner && !equal(determinant, 0.f) && dist < 1.f) {
				vec2 delta = p3 - p0;
				float t = (delta.x * v32.y - delta.y * v32.x) / determinant;
				vec2 intersection = p0 + t * v10;

				chain.pop_back();
				chain.at(0) = intersection;
			}
		}

		// case 2
		{
			vec2 p3 = chain.at(chain.size() - 1);
			vec2 p2 = chain.at(0);
			vec2 p1 = chain.at(1);
			vec2 p0 = chain.at(2);

			vec2 v10 = p1 - p0;
			vec2 v32 = p2 - p3;

			bool corner =  (v10.x == 0.f || v10.y == 0.f)
						&& (v32.x == 0.f || v32.y == 0.f);

			float determinant = v10.x * v32.y - v10.y * v32.x;

			float dist = distance(p1, p2);

			if (corner && !equal(determinant, 0.f) && dist < 1.f) {
				vec2 delta = p3 - p0;
				float t = (delta.x * v32.y - delta.y * v32.x) / determinant;
				vec2 intersection = p0 + t * v10;

				chain.erase(chain.begin());
				chain.at(0) = intersection;
			}
		}

		// 3.4 Remove caps
		//     There is 3 cases?

		// case 1
		{
			vec2 p4 = chain.at(chain.size() - 1);
			vec2 p3 = chain.at(0);
			vec2 p2 = chain.at(1);
			vec2 p1 = chain.at(2);
			vec2 p0 = chain.at(3);

			vec2 v10 = p1 - p0;
			vec2 v21 = p2 - p1;
			vec2 v32 = p2 - p3;
			vec2 v43 = p3 - p4;

			float determinant = v10.x * v43.y - v10.y * v43.x;

			bool tunnel = equal(determinant, 0.f);
			bool endcap = equal(dot(v21, v32), 0.f);

			float distSqr21 = dot(v21, v21); // only consider close points
			float distSqr32 = dot(v32, v32);

			if (tunnel && endcap && distSqr21 < 1.f && distSqr32 < 1.f) {
				vec2 new0;
				vec2 new1;

				// Figure out which direction this cap is
				if (v10.x == 0.f) {
					new0 = vec2(p3.x, p2.y);
					new1 = vec2(p1.x, p2.y);
				}

				else {
					new0 = vec2(p2.x, p3.y);
					new1 = vec2(p2.x, p1.y);
				}

				chain.at(0) = new0;
				chain.at(2) = new1;
				chain.erase(chain.begin() + 1);
			}
		}

		// case 2
		{
			vec2 p4 = chain.at(chain.size() - 2);
			vec2 p3 = chain.at(chain.size() - 1);
			vec2 p2 = chain.at(0);
			vec2 p1 = chain.at(1);
			vec2 p0 = chain.at(2);

			vec2 v10 = p1 - p0;
			vec2 v21 = p2 - p1;
			vec2 v32 = p2 - p3;
			vec2 v43 = p3 - p4;

			float determinant = v10.x * v43.y - v10.y * v43.x;

			bool tunnel = equal(determinant, 0.f);
			bool endcap = equal(dot(v21, v32), 0.f);

			float distSqr21 = dot(v21, v21); // only consider close points
			float distSqr32 = dot(v32, v32);

			if (tunnel && endcap && distSqr21 < 1.f && distSqr32 < 1.f) {
				vec2 new0;
				vec2 new1;

				// Figure out which direction this cap is
				if (v10.x == 0.f) {
					new0 = vec2(p3.x, p2.y);
					new1 = vec2(p1.x, p2.y);
				}

				else {
					new0 = vec2(p2.x, p3.y);
					new1 = vec2(p2.x, p1.y);
				}

				chain.at(chain.size() - 1) = new0;
				chain.at(1) = new1;
				chain.erase(chain.begin() + 0);
			}
		}

		// case 3
		{
			vec2 p4 = chain.at(chain.size() - 3);
			vec2 p3 = chain.at(chain.size() - 2);
			vec2 p2 = chain.at(chain.size() - 1);
			vec2 p1 = chain.at(0);
			vec2 p0 = chain.at(1);

			vec2 v10 = p1 - p0;
			vec2 v21 = p2 - p1;
			vec2 v32 = p2 - p3;
			vec2 v43 = p3 - p4;

			float determinant = v10.x * v43.y - v10.y * v43.x;

			bool tunnel = equal(determinant, 0.f);
			bool endcap = equal(dot(v21, v32), 0.f);

			float distSqr21 = dot(v21, v21); // only consider close points
			float distSqr32 = dot(v32, v32);

			if (tunnel && endcap && distSqr21 < 1.f && distSqr32 < 1.f) {
				vec2 new0;
				vec2 new1;

				// Figure out which direction this cap is
				if (v10.x == 0.f) {
					new0 = vec2(p3.x, p2.y);
					new1 = vec2(p1.x, p2.y);
				}

				else {
					new0 = vec2(p2.x, p3.y);
					new1 = vec2(p2.x, p1.y);
				}

				chain.at(chain.size() - 2) = new0;
				chain.at(0) = new1;
				chain.erase(chain.begin() + chain.size() - 1);
			}
		}

		// Verify can remove
		for (size_t i = 0; i < chain.size(); i++) {
			vec2 p4 = chain.at( i );
			vec2 p3 = chain.at( (i + 1) % chain.size() );
			vec2 p2 = chain.at( (i + 2) % chain.size() );
			vec2 p1 = chain.at( (i + 3) % chain.size() );
			vec2 p0 = chain.at( (i + 4) % chain.size() );

			vec2 v10 = p1 - p0;
			vec2 v21 = p1 - p2;
			vec2 v32 = p2 - p3;
			vec2 v43 = p3 - p4;

			bool colinear = equal(cross(v10, v21), 0.f);

			if (colinear) {
				printf("colinear %zd\n", i);
			}

			bool corner =  (v10.x == 0.f || v10.y == 0.f)
						&& (v32.x == 0.f || v32.y == 0.f);

			float determinant0123 = v10.x * v32.y - v10.y * v32.x;
			float dist = distance(p1, p2);

			if (corner && !equal(determinant0123, 0.f) && dist < 1.f) {
				printf("corner %zd\n", i);
			}

			float determinant0134 = v10.x * v43.y - v10.y * v43.x;

			bool tunnel = equal(determinant0134, 0.f);
			bool endcap = equal(dot(v21, v32), 0.f);

			float distSqr21 = dot(v21, v21); // only consider close points
			float distSqr32 = dot(v32, v32);

			if (tunnel && endcap && distSqr21 < 1.f && distSqr32 < 1.f) {
				printf("cap\n");
			}
		}

		// chain = simplify(chain, 0.4f);

		chains.emplace_back(std::move(chain));
	}

    std::vector<std::vector<std::vector<vec2>>> polygons;

    for (const auto& chain : chains) {
        bool isHole = false;

        for (auto& polygon : polygons) {
            if (isPointInPolygon(chain[0], polygon[0])) {
                polygon.push_back(chain);
                isHole = true;
                break;
            }
        }

        if (!isHole) {
            polygons.push_back({chain});
        }
    }

	return polygons;
}

std::vector<int> MarchingSquares_Triangulate(const std::vector<std::vector<vec2>>& chains) {

	std::vector<int> triangles = mapbox::earcut<int>(chains);

	return triangles;
}
