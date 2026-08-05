public module ray_sphere_intersection;

import math;

// The ray-sphere intersection logic is from
// https://github.com/ebruneton/precomputed_atmospheric_scattering.
// License:
/*
Copyright (c) 2017 Eric Bruneton
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
this list of conditions and the following disclaimer in the documentation
and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its contributors
may be used to endorse or promote products derived from this software without
specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

float2 intersect_sphere(float mu, float r, float sphere_radius) {
	float discriminant = r * r * (mu * mu - 1.0) + pow2(sphere_radius);

	if (discriminant < 0.0) {
		return float2(-1.0);
	}

	discriminant = sqrt(discriminant);
	return -r * mu + float2(-discriminant, discriminant);
}

float2
intersect_sphere(float3 ray_origin, float3 ray_dir, float sphere_radius) {
	float b = dot(ray_origin, ray_dir);
	float discriminant
		= pow2(b) - dot(ray_origin, ray_origin) + pow2(sphere_radius);

	if (discriminant < 0.0) {
		return float2(-1.0);
	}

	discriminant = sqrt(discriminant);
	return -b + float2(-discriminant, discriminant);
}

float2 intersect_spherical_shell(
	float mu,
	float r,
	float inner_sphere_radius,
	float outer_sphere_radius
) {
	float2 inner_sphere_dists = intersect_sphere(mu, r, inner_sphere_radius);
	float2 outer_sphere_dists = intersect_sphere(mu, r, outer_sphere_radius);

	bool inner_sphere_intersected = inner_sphere_dists.y >= 0.0;
	bool outer_sphere_intersected = outer_sphere_dists.y >= 0.0;

	if (!outer_sphere_intersected) {
		return float2(-1.0);
	}

	float2 dists;
	dists.x = inner_sphere_intersected && inner_sphere_dists.x < 0.0
		? inner_sphere_dists.y
		: max0(outer_sphere_dists.x);
	dists.y = inner_sphere_intersected && inner_sphere_dists.x > 0.0
		? inner_sphere_dists.x
		: outer_sphere_dists.y;

	return dists;
}

float2 intersect_spherical_shell(
	float3 ray_origin,
	float3 ray_dir,
	float inner_sphere_radius,
	float outer_sphere_radius
) {
	float2 inner_sphere_dists
		= intersect_sphere(ray_origin, ray_dir, inner_sphere_radius);
	float2 outer_sphere_dists
		= intersect_sphere(ray_origin, ray_dir, outer_sphere_radius);

	bool inner_sphere_intersected = inner_sphere_dists.y >= 0.0;
	bool outer_sphere_intersected = outer_sphere_dists.y >= 0.0;

	if (!outer_sphere_intersected) {
		return float2(-1.0);
	}

	float2 dists;
	dists.x = inner_sphere_intersected && inner_sphere_dists.x < 0.0
		? inner_sphere_dists.y
		: max0(outer_sphere_dists.x);
	dists.y = inner_sphere_intersected && inner_sphere_dists.x > 0.0
		? inner_sphere_dists.x
		: outer_sphere_dists.y;

	return dists;
}


