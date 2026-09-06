#pragma once

#include "ArrayView.h"

#include "glm/vec2.hpp"
using namespace glm;

#include <vector>

#include "SpriteCell.h"

// Output a list of connections
// Each 2 elements is an edge
// The points are not culled to remove duplicates so there will always be 2x the number of points
// They are ordered by the internal iterations not by what could be considered an outline.
std::vector<vec2> marching_squares(int width, int height, const ArrayView<SpriteCellMask>& mask);

// Take the unordered list of edges and create a list of chains.
// Some assumptions:
// 1. Any mask passed into these algorithms has already been passed to the SpriteCutter:
//      This assures that if there is more than 1 chain, that polygon has to be a hole in the larger polygon.
// 2. The edges argument should be the output of marching_squares:
//      This assures that the outer polygon must contain the first point in edges.
// 
// The first vector will be the outer polygon, and the next ones will be any holes
std::vector<std::vector<std::vector<vec2>>> MarchingSquares_CreateChains(const std::vector<vec2>& edges);

// Take the list of chains and convert it into a list of vertex indices
// Each triplet is a triangle. If the index is larger than a chains size, its in the next chain
std::vector<int> MarchingSquares_Triangulate(const std::vector<std::vector<vec2>>& chains);