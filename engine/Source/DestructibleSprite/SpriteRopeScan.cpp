#include "Containers/VectorUtil.h"
#include "SpriteRopeScan.h"

#include <algorithm>
#include <climits>
#include <godot_cpp/templates/rb_set.hpp>
#include <godot_cpp/templates/pair.hpp>
#include <godot_cpp/templates/local_vector.hpp>

static const int k_n8x[8] = {-1, 0, 1, -1, 1, -1, 0, 1};
static const int k_n8y[8] = {-1, -1, -1, 0, 0, 1, 1, 1};

static const int k_cycx[8] = {0, 1, 1, 1, 0, -1, -1, -1};
static const int k_cycy[8] = {-1, -1, 0, 1, 1, 1, 0, -1};

static bool is_structural(SpriteCellMaskType t) {
    return t != SpriteCellMaskType_Empty && t != SpriteCellMaskType_Rope;
}

static bool is_joint_cell(SpriteCellMaskType t) {
    return t >= SpriteCellMaskType_Joint1 && t <= SpriteCellMaskType_Joint4;
}

struct ScanIsland {
    godot::LocalVector<int> cells;
    Color4 color;
};

struct ScanCluster {
    int island;
    int rep;
    godot::LocalVector<int> cells;
    godot::LocalVector<godot::Pair<int, int>> incident;
};

struct ScanSegment {
    int island;
    godot::LocalVector<godot::Vector2i> path;
    int cluster_a = -1;
    int cluster_b = -1;
    int type_a = SpriteRopeAnchorType_Free;
    int type_b = SpriteRopeAnchorType_Free;
    int touch_a = -1;
    int touch_b = -1;
    int cell_type_a = SpriteCellMaskType_Empty;
    int cell_type_b = SpriteCellMaskType_Empty;
};

static void thin_island(const godot::LocalVector<int>& cells, godot::LocalVector<uint8_t>& skel, int w, int h) {
    auto at = [&](int x, int y) {
        if (x < 0 || y < 0 || x >= w || y >= h) {
            return 0;
        }

        return (int)skel[x + y * w];
    };

    godot::LocalVector<int> kill;
    bool changed = true;

    while (changed) {
        changed = false;

        for (int step = 0; step < 2; step++) {
            kill.clear();

            for (int index : cells) {
                if (!skel[index]) {
                    continue;
                }

                int x = index % w;
                int y = index / w;

                int p[8] = {at(x, y - 1), at(x + 1, y - 1), at(x + 1, y), at(x + 1, y + 1), at(x, y + 1), at(x - 1, y + 1), at(x - 1, y), at(x - 1, y - 1)};

                int b = p[0] + p[1] + p[2] + p[3] + p[4] + p[5] + p[6] + p[7];

                if (b < 2 || b > 6) {
                    continue;
                }

                int a = 0;

                for (int k = 0; k < 8; k++) {
                    if (p[k] == 0 && p[(k + 1) % 8] == 1) {
                        a += 1;
                    }
                }

                if (a != 1) {
                    continue;
                }

                if (step == 0) {
                    if (p[0] * p[2] * p[4] != 0 || p[2] * p[4] * p[6] != 0) {
                        continue;
                    }
                }
                else {
                    if (p[0] * p[2] * p[6] != 0 || p[0] * p[4] * p[6] != 0) {
                        continue;
                    }
                }

                kill.push_back(index);
            }

            for (int index : kill) {
                skel[index] = 0;
            }

            if (!kill.is_empty()) {
                changed = true;
            }
        }
    }
}

godot::LocalVector<ScannedRope> scan_sprite_ropes(const godot::LocalVector<SpriteCellMaskType>& mask, const godot::LocalVector<Color4>& pixels, int w, int h) {
    godot::LocalVector<ScannedRope> result;

    if (w <= 0 || h <= 0) {
        return result;
    }

    godot::LocalVector<int> group_id; vector_fill(group_id, w * h, -1);
    godot::LocalVector<ScanIsland> islands;

    for (int seed = 0; seed < w * h; seed++) {
        if (mask[seed] != SpriteCellMaskType_Rope || group_id[seed] != -1) {
            continue;
        }

        int gid = (int)islands.size();
        ScanIsland island {};

        long long sum_r = 0;
        long long sum_g = 0;
        long long sum_b = 0;

        godot::LocalVector<int> stack;
        stack.push_back(seed);
        group_id[seed] = gid;

        while (!stack.is_empty()) {
            int index = stack[stack.size() - 1];
            stack.remove_at(stack.size() - 1);

            int x = index % w;
            int y = index / w;

            island.cells.push_back(index);

            sum_r += pixels[index].r;
            sum_g += pixels[index].g;
            sum_b += pixels[index].b;

            for (int k = 0; k < 8; k++) {
                int nx = x + k_n8x[k];
                int ny = y + k_n8y[k];

                if (nx < 0 || ny < 0 || nx >= w || ny >= h) {
                    continue;
                }

                int ni = nx + ny * w;

                if (mask[ni] == SpriteCellMaskType_Rope && group_id[ni] == -1) {
                    group_id[ni] = gid;
                    stack.push_back(ni);
                }
            }
        }

        int count = (int)island.cells.size();
        island.color = Color4((uint8_t)(sum_r / count), (uint8_t)(sum_g / count), (uint8_t)(sum_b / count), (uint8_t)255);

        islands.push_back(std::move(island));
    }

    godot::LocalVector<uint8_t> skel; vector_fill(skel, w * h, 0);
    godot::LocalVector<uint8_t> visited; vector_fill(visited, w * h, 0);
    godot::LocalVector<int> degree; vector_fill(degree, w * h, 0);
    godot::LocalVector<int> cluster_of; vector_fill(cluster_of, w * h, -1);
    godot::LocalVector<int> terminal_of; vector_fill(terminal_of, w * h, -1);

    godot::LocalVector<ScanCluster> clusters;
    godot::LocalVector<ScanSegment> segments;
    godot::LocalVector<godot::LocalVector<int>> island_segments; island_segments.resize(islands.size());

    auto pos_of = [&](int index) {
        return godot::Vector2i(index % w, index / w);
    };

    for (int gid = 0; gid < (int)islands.size(); gid++) {
        ScanIsland& island = islands[gid];

        for (int index : island.cells) {
            skel[index] = 1;
        }

        thin_island(island.cells, skel, w, h);

        auto skel_neighbors = [&](int index, int out[8]) {
            int x = index % w;
            int y = index / w;
            int count = 0;

            for (int k = 0; k < 8; k++) {
                int nx = x + k_n8x[k];
                int ny = y + k_n8y[k];

                if (nx < 0 || ny < 0 || nx >= w || ny >= h) {
                    continue;
                }

                int ni = nx + ny * w;

                if (skel[ni]) {
                    out[count] = ni;
                    count += 1;
                }
            }

            return count;
        };

        auto branch_count = [&](int index) {
            int x = index % w;
            int y = index / w;

            int p[8];

            for (int k = 0; k < 8; k++) {
                int nx = x + k_cycx[k];
                int ny = y + k_cycy[k];

                p[k] = nx >= 0 && ny >= 0 && nx < w && ny < h ? (int)skel[nx + ny * w] : 0;
            }

            int a = 0;

            for (int k = 0; k < 8; k++) {
                if (p[k] == 0 && p[(k + 1) % 8] == 1) {
                    a += 1;
                }
            }

            return a;
        };

        godot::LocalVector<int> skel_cells;

        for (int index : island.cells) {
            if (!skel[index]) {
                continue;
            }

            skel_cells.push_back(index);

            int n8[8];
            degree[index] = skel_neighbors(index, n8);
        }

        int cluster_base = (int)clusters.size();

        for (int index : skel_cells) {
            if (branch_count(index) < 3 || cluster_of[index] != -1) {
                continue;
            }

            int cid = (int)clusters.size();
            ScanCluster cluster {gid, index, {}, {}};

            godot::LocalVector<int> stack;
            stack.push_back(index);
            cluster_of[index] = cid;

            while (!stack.is_empty()) {
                int cur = stack[stack.size() - 1];
                stack.remove_at(stack.size() - 1);

                cluster.cells.push_back(cur);

                int n8[8];
                int count = skel_neighbors(cur, n8);

                for (int k = 0; k < count; k++) {
                    if (branch_count(n8[k]) >= 3 && cluster_of[n8[k]] == -1) {
                        cluster_of[n8[k]] = cid;
                        stack.push_back(n8[k]);
                    }
                }
            }

            godot::Vector2i sum(0, 0);

            for (int cell : cluster.cells) {
                sum += pos_of(cell);
            }

            int best = INT_MAX;

            for (int cell : cluster.cells) {
                godot::Vector2i d = pos_of(cell) * (int)cluster.cells.size() - sum;
                int dd = d.x * d.x + d.y * d.y;

                if (dd < best) {
                    best = dd;
                    cluster.rep = cell;
                }
            }

            clusters.push_back(std::move(cluster));
        }

        struct ScanTerminal {
            int cell;
            int cluster;
        };

        godot::LocalVector<ScanTerminal> terminals;

        for (int index : skel_cells) {
            if (cluster_of[index] == -1 && degree[index] <= 1) {
                terminal_of[index] = (int)terminals.size();
                terminals.push_back({index, -1});
            }
        }

        for (int cid = cluster_base; cid < (int)clusters.size(); cid++) {
            int ti = (int)terminals.size();
            terminals.push_back({clusters[cid].rep, cid});

            for (int cell : clusters[cid].cells) {
                terminal_of[cell] = ti;
            }
        }

        auto pick_step = [&](int cur, int prev) {
            int c8[8];
            int ccount = skel_neighbors(cur, c8);

            int terminal_step = -1;
            int orth_step = -1;
            int diag_step = -1;

            int cx = cur % w;
            int cy = cur / w;

            for (int m = 0; m < ccount; m++) {
                int cand = c8[m];

                if (cand == prev) {
                    continue;
                }

                if (terminal_of[cand] != -1) {
                    if (terminal_step == -1) {
                        terminal_step = cand;
                    }

                    continue;
                }

                if (visited[cand]) {
                    continue;
                }

                int dx = cand % w - cx;
                int dy = cand / w - cy;

                if (dx * dy == 0) {
                    if (orth_step == -1) {
                        orth_step = cand;
                    }
                }
                else if (diag_step == -1) {
                    diag_step = cand;
                }
            }

            if (terminal_step != -1) {
                return terminal_step;
            }

            if (orth_step != -1) {
                return orth_step;
            }

            return diag_step;
        };

        godot::RBSet<godot::Pair<int, int>> direct_edges;

        auto emit = [&](godot::LocalVector<godot::Vector2i>&& path, int cluster_front, int cluster_back) {
            int seg = (int)segments.size();

            ScanSegment segment {};
            segment.island = gid;
            segment.path = std::move(path);
            segment.cluster_a = cluster_front;
            segment.cluster_b = cluster_back;

            if (cluster_front != -1) {
                clusters[cluster_front].incident.push_back({seg, 0});
            }

            if (cluster_back != -1) {
                clusters[cluster_back].incident.push_back({seg, 1});
            }

            segments.push_back(std::move(segment));
            island_segments[gid].push_back(seg);
        };

        for (int ti = 0; ti < (int)terminals.size(); ti++) {
            const ScanTerminal& terminal = terminals[ti];

            godot::LocalVector<int> ports;

            if (terminal.cluster == -1) {
                ports.push_back(terminal.cell);
            }
            else {
                ports = clusters[terminal.cluster].cells;
            }

            for (int port : ports) {
                int n8[8];
                int count = skel_neighbors(port, n8);

                for (int k = 0; k < count; k++) {
                    int next = n8[k];

                    if (terminal_of[next] == ti) {
                        continue;
                    }

                    if (terminal_of[next] != -1) {
                        int tj = terminal_of[next];
                        auto edge = godot::Pair<int, int>{std::min(ti, tj), std::max(ti, tj)};

                        if (direct_edges.has(edge)) {
                            continue;
                        }

                        direct_edges.insert(edge);

                        emit({pos_of(terminal.cell), pos_of(terminals[tj].cell)}, terminal.cluster, terminals[tj].cluster);
                        continue;
                    }

                    if (visited[next]) {
                        continue;
                    }

                    godot::LocalVector<godot::Vector2i> path;
                    path.push_back(pos_of(terminal.cell));

                    int prev = port;
                    int cur = next;
                    int end_cluster = -1;

                    while (true) {
                        visited[cur] = 1;
                        path.push_back(pos_of(cur));

                        int step = pick_step(cur, prev);

                        if (step == -1) {
                            break;
                        }

                        if (terminal_of[step] != -1) {
                            int tj = terminal_of[step];
                            path.push_back(pos_of(terminals[tj].cell));
                            end_cluster = terminals[tj].cluster;
                            break;
                        }

                        prev = cur;
                        cur = step;
                    }

                    emit(std::move(path), terminal.cluster, end_cluster);
                }
            }
        }

        for (int index : skel_cells) {
            if (degree[index] != 2 || cluster_of[index] != -1 || visited[index] || terminal_of[index] != -1) {
                continue;
            }

            godot::LocalVector<godot::Vector2i> path;
            path.push_back(pos_of(index));
            visited[index] = 1;

            int prev = index;
            int cur = pick_step(index, index);

            while (cur != -1 && cur != index && !visited[cur]) {
                visited[cur] = 1;
                path.push_back(pos_of(cur));

                int step = pick_step(cur, prev);

                if (step == -1) {
                    break;
                }

                prev = cur;
                cur = step;
            }

            path.push_back(pos_of(index));

            emit(std::move(path), -1, -1);
        }

        if (island_segments[gid].is_empty() && !skel_cells.is_empty()) {
            emit({pos_of(skel_cells[0]), pos_of(skel_cells[0])}, -1, -1);
        }

        for (int seg : island_segments[gid]) {
            if (segments[seg].path.size() < 2) {
                segments[seg].path.push_back(segments[seg].path[0]);
            }
        }

        for (int index : island.cells) {
            skel[index] = 0;
            visited[index] = 0;
            degree[index] = 0;
            cluster_of[index] = -1;
            terminal_of[index] = -1;
        }
    }

    auto check_around = [&](godot::Vector2i c, int self_gid, bool& found_struct, int& joint_type, int& found_rope) {
        for (int k = 0; k < 8; k++) {
            int nx = c.x + k_n8x[k];
            int ny = c.y + k_n8y[k];

            if (nx < 0 || ny < 0 || nx >= w || ny >= h) {
                continue;
            }

            int ni = nx + ny * w;

            if (is_structural(mask[ni])) {
                found_struct = true;

                if (is_joint_cell(mask[ni]) && joint_type == SpriteCellMaskType_Empty) {
                    joint_type = mask[ni];
                }
            }

            else if (mask[ni] == SpriteCellMaskType_Rope && group_id[ni] != self_gid && group_id[ni] != -1) {
                found_rope = group_id[ni];
            }
        }
    };

    auto classify = [&](godot::Vector2i c, int self_gid, int& out_type, int& out_touch, int& out_cell_type) {
        out_type = SpriteRopeAnchorType_Free;
        out_touch = -1;
        out_cell_type = SpriteCellMaskType_Empty;

        bool found_struct = false;
        int joint_type = SpriteCellMaskType_Empty;
        int found_rope = -1;

        check_around(c, self_gid, found_struct, joint_type, found_rope);

        if (!found_struct && found_rope == -1) {
            for (int k = 0; k < 8; k++) {
                int nx = c.x + k_n8x[k];
                int ny = c.y + k_n8y[k];

                if (nx < 0 || ny < 0 || nx >= w || ny >= h) {
                    continue;
                }

                int ni = nx + ny * w;

                if (mask[ni] == SpriteCellMaskType_Rope && group_id[ni] == self_gid) {
                    check_around(godot::Vector2i(nx, ny), self_gid, found_struct, joint_type, found_rope);
                }
            }
        }

        if (found_struct) {
            out_type = SpriteRopeAnchorType_Cell;
            out_cell_type = joint_type;
        }

        else if (found_rope != -1) {
            out_type = SpriteRopeAnchorType_Rope;
            out_touch = found_rope;
        }
    };

    for (ScanSegment& segment : segments) {
        classify(segment.path[0], segment.island, segment.type_a, segment.touch_a, segment.cell_type_a);
        classify(segment.path[segment.path.size() - 1], segment.island, segment.type_b, segment.touch_b, segment.cell_type_b);
    }

    for (ScanCluster& cluster : clusters) {
        if (cluster.incident.is_empty()) {
            continue;
        }

        auto far_is_cell = [&](godot::Pair<int, int> inc) {
            const ScanSegment& segment = segments[inc.first];
            return (inc.second == 0 ? segment.type_b : segment.type_a) == SpriteRopeAnchorType_Cell;
        };

        godot::Pair<int, int> owner = cluster.incident[0];

        for (const godot::Pair<int, int>& inc : cluster.incident) {
            if (far_is_cell(inc) && !far_is_cell(owner)) {
                owner = inc;
            }
            else if (far_is_cell(inc) == far_is_cell(owner) && segments[inc.first].path.size() > segments[owner.first].path.size()) {
                owner = inc;
            }
        }

        const ScanSegment& owner_segment = segments[owner.first];
        godot::Vector2i rep = pos_of(cluster.rep);
        int owner_node = owner_segment.path[0] == rep ? 0 : (int)owner_segment.path.size() - 1;

        for (const godot::Pair<int, int>& inc : cluster.incident) {
            if (inc == owner) {
                continue;
            }

            ScanSegment& segment = segments[inc.first];

            if (inc.second == 0) {
                segment.type_a = SpriteRopeAnchorType_Rope;
                segment.cell_type_a = SpriteCellMaskType_Empty;
                segment.touch_a = -2 - owner.first;
                segment.cluster_a = owner_node;
            }
            else {
                segment.type_b = SpriteRopeAnchorType_Rope;
                segment.cell_type_b = SpriteCellMaskType_Empty;
                segment.touch_b = -2 - owner.first;
                segment.cluster_b = owner_node;
            }
        }
    }

    auto nearest_node = [&](int gid, godot::Vector2i c, int& out_rope, int& out_node) {
        out_rope = -1;
        out_node = -1;

        int bestd = INT_MAX;

        for (int seg : island_segments[gid]) {
            const godot::LocalVector<godot::Vector2i>& p = segments[seg].path;

            for (int i = 0; i < (int)p.size(); i++) {
                godot::Vector2i d = p[i] - c;
                int dd = d.x * d.x + d.y * d.y;

                if (dd < bestd) {
                    bestd = dd;
                    out_rope = seg;
                    out_node = i;
                }
            }
        }
    };

    auto resolve_anchor = [&](const ScanSegment& segment, int end, SpriteRopeAnchor& out) {
        int type = end == 0 ? segment.type_a : segment.type_b;
        int touch = end == 0 ? segment.touch_a : segment.touch_b;
        int cell_type = end == 0 ? segment.cell_type_a : segment.cell_type_b;
        godot::Vector2i cell = end == 0 ? segment.path[0] : segment.path[segment.path.size() - 1];

        out.type = type;
        out.cell = cell;
        out.rope_index = -1;
        out.node_index = -1;
        out.cell_type = cell_type;

        if (type != SpriteRopeAnchorType_Rope) {
            return;
        }

        if (touch <= -2) {
            out.rope_index = -2 - touch;
            out.node_index = end == 0 ? segment.cluster_a : segment.cluster_b;
        }

        else if (touch >= 0) {
            nearest_node(touch, cell, out.rope_index, out.node_index);
        }

        else {
            out.type = SpriteRopeAnchorType_Free;
        }
    };

    for (const ScanSegment& segment : segments) {
        ScannedRope r {};
        r.color = islands[segment.island].color;
        r.path = segment.path;

        resolve_anchor(segment, 0, r.a);
        resolve_anchor(segment, 1, r.b);

        result.push_back(std::move(r));
    }

    return result;
}
