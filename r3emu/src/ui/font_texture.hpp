#include "../sdl/texture.hpp"

namespace r3emu::ui
{
	class font_texture : public sdl::texture
	{
	public:
		font_texture(SDL_Renderer *renderer);
	};
}
