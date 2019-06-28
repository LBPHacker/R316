#include <sdlstuff/texture.hpp>

namespace r3emu::ui
{
	class font_texture : public sdlstuff::texture
	{
	public:
		font_texture(SDL_Renderer *renderer);
	};
}
